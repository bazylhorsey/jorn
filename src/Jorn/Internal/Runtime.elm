module Jorn.Internal.Runtime exposing (Config, Message(..), Ports, Routing, Screen, Start(..), State, program)

{-| The loop every app needs: mount the view, route each event to its
handler, call `update`, diff, and send the patches to `client/jorn.js`.
`Jorn` and `Jorn.Navigation` make their programs with it.

A program that routes waits for the page to say where it is before it
starts, since its `init` takes the URL. Addresses travel as strings, and the
program that routes turns them into `Url`s.

-}

import Jorn.Effect exposing (Effect)
import Jorn.Element exposing (Element)
import Jorn.Internal.Effect as Effect exposing (Item(..))
import Jorn.Internal.Event as Events
import Jorn.Internal.Patch
import Jorn.Internal.Vdom as Vdom
import Jorn.Patch
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)


type alias Ports msg =
    { toJorn : Value -> Cmd (Message msg)
    , fromJorn : (Value -> Message msg) -> Sub (Message msg)
    }


type State model msg
    = Waiting (String -> Maybe ( model, Effect msg ))
    | Running (Live model msg)
    | Stopped


type alias Live model msg =
    { model : model
    , screen : Element msg
    , title : Maybe String
    , url : String
    , frameRequested : Bool
    , beforePaint : List msg
    , afterPaint : List msg
    , painting : List msg
    , instructions : List Value
    }


type Message msg
    = FromClient Value
    | Got msg


type alias Config flags model msg =
    { init : flags -> Start model msg
    , update : msg -> model -> ( model, Effect msg )
    , view : model -> Screen msg
    , subscriptions : model -> Sub msg
    , ports : Ports msg
    , routing : Maybe (Routing msg)
    }


{-| A program starts straight away, or once it knows the page's address. The
function gives `Nothing` for an address the program can't read.
-}
type Start model msg
    = Now ( model, Effect msg )
    | AtUrl (String -> Maybe ( model, Effect msg ))


{-| What a view gives the runtime. A program with a `title` sets the page's.
-}
type alias Screen msg =
    { title : Maybe String
    , body : Element msg
    }


{-| How a program that routes hears about addresses: the page's address
changed, or someone clicked a link (given the current address and the
link's). `onUrlChange` gives `Nothing` for an address it can't read.
-}
type alias Routing msg =
    { onUrlChange : String -> Maybe msg
    , onLink : String -> String -> msg
    }


program : Config flags model msg -> Platform.Program flags (State model msg) (Message msg)
program config =
    Platform.worker
        { init =
            \flags ->
                case config.init flags of
                    Now started ->
                        begin config "" started

                    AtUrl starting ->
                        ( Waiting starting, Cmd.none )
        , update = step config
        , subscriptions =
            \state ->
                case state of
                    Waiting _ ->
                        config.ports.fromJorn FromClient

                    Running live ->
                        Sub.batch [ config.ports.fromJorn FromClient, Sub.map Got (config.subscriptions live.model) ]

                    Stopped ->
                        Sub.none
        }


begin : Config flags model msg -> String -> ( model, Effect msg ) -> ( State model msg, Cmd (Message msg) )
begin config url ( model, effect ) =
    let
        view =
            config.view model

        initial =
            { model = model

            -- Memos keep what they build, so events and the next diff don't
            -- build them again.
            , screen = Maybe.withDefault view.body (Vdom.build view.body)
            , title = view.title
            , url = url
            , frameRequested = False
            , beforePaint = []
            , afterPaint = []
            , painting = []
            , instructions = []
            }

        ( live, cmd ) =
            perform config effect initial
    in
    ( Running live
    , Cmd.batch [ config.ports.toJorn (mount config live False), cmd ]
    )


{-| The whole view, saying whether the page should follow links and the
browser's history for the program, and what the page's title is.
-}
mount : Config flags model msg -> Live model msg -> Bool -> Value
mount config live painted =
    Encode.object
        (( "mount", Jorn.Patch.encodeHtml live.screen )
            :: List.filterMap identity
                [ ifTrue painted ( "painted", Encode.bool True )
                , Maybe.map (\_ -> ( "routing", Encode.bool True )) config.routing
                , Maybe.map (\title -> ( "title", Encode.string title )) live.title
                ]
        )


ifTrue : Bool -> a -> Maybe a
ifTrue yes value =
    if yes then
        Just value

    else
        Nothing


step : Config flags model msg -> Message msg -> State model msg -> ( State model msg, Cmd (Message msg) )
step config message state =
    case state of
        Stopped ->
            ( state, Cmd.none )

        Waiting starting ->
            case message of
                FromClient value ->
                    case Decode.decodeValue incoming value of
                        Ok (Url url) ->
                            case starting url of
                                Just started ->
                                    begin config url started

                                Nothing ->
                                    ( state, send config "error" (Encode.string (unreadable url)) )

                        Ok Shutdown ->
                            ( Stopped, Cmd.none )

                        -- Nothing else means anything before the program
                        -- has started.
                        _ ->
                            ( state, Cmd.none )

                Got _ ->
                    ( state, Cmd.none )

        Running live ->
            case message of
                Got msg ->
                    running (updateWith config msg live)

                FromClient value ->
                    case Decode.decodeValue incoming value of
                        Ok Shutdown ->
                            ( Stopped, Cmd.none )

                        Ok kind ->
                            running (receive config kind live)

                        Err problem ->
                            ( state, send config "error" (Encode.string (Decode.errorToString problem)) )


running : ( Live model msg, Cmd (Message msg) ) -> ( State model msg, Cmd (Message msg) )
running =
    Tuple.mapFirst Running


unreadable : String -> String
unreadable url =
    "Can't start at " ++ url ++ ": a program with URL routing needs an http or https address"


receive : Config flags model msg -> Incoming -> Live model msg -> ( Live model msg, Cmd (Message msg) )
receive config kind live =
    case kind of
        Event event ->
            case Events.route event live.screen of
                Ok msg ->
                    updateWith config msg live

                Err problem ->
                    ( live, send config "error" (Encode.string (Events.errorToString problem)) )

        Decide event reply ->
            case Events.decide event live.screen of
                Ok handler ->
                    -- Reading `reply` is the answer, so what decoding it
                    -- returns doesn't matter.
                    case Decode.decodeValue (answer handler) reply of
                        Ok () ->
                            ( live, Cmd.none )

                        Err _ ->
                            ( live, Cmd.none )

                Err _ ->
                    ( live, Cmd.none )

        Frame ->
            render config live

        Painted ->
            List.foldl (\msg acc -> andThen (updateWith config msg) acc) ( { live | painting = [] }, Cmd.none ) live.painting

        Remount ->
            ( live, config.ports.toJorn (mount config live (not (List.isEmpty live.painting))) )

        Url url ->
            case config.routing of
                Just routing ->
                    case routing.onUrlChange url of
                        Just msg ->
                            updateWith config msg { live | url = url }

                        Nothing ->
                            ( live, send config "error" (Encode.string ("Can't read the address " ++ url)) )

                -- Every page says where it is. Only a program that routes
                -- cares.
                Nothing ->
                    ( live, Cmd.none )

        Link href ->
            case config.routing of
                Just routing ->
                    updateWith config (routing.onLink live.url href) live

                Nothing ->
                    ( live, Cmd.none )

        Shutdown ->
            ( live, Cmd.none )


{-| What the page sends: an event, a question about an event that's still
firing, the animation frame we asked for, word that the last patches are on
the page, a request for the whole view because the page lost track of it,
the page's address, a link someone clicked, or a request to stop.

The question comes with a reply object to answer on (see `answer`). Nothing
else happens: the event itself follows as an ordinary `Event`.

-}
type Incoming
    = Event Events.Incoming
    | Decide Events.Incoming Value
    | Frame
    | Painted
    | Remount
    | Url String
    | Link String
    | Shutdown


incoming : Decode.Decoder Incoming
incoming =
    Decode.oneOf
        [ Decode.field "event" (Decode.map Event Events.decoder)
        , Decode.map2 Decide (Decode.field "decide" Events.decoder) (Decode.field "reply" Decode.value)
        , Decode.field "frame" (Decode.succeed Frame)
        , Decode.field "painted" (Decode.succeed Painted)
        , Decode.field "remount" (Decode.succeed Remount)
        , Decode.field "url" (Decode.map Url Decode.string)
        , Decode.field "link" (Decode.map Link Decode.string)
        , Decode.field "shutdown" (Decode.succeed Shutdown)
        ]


{-| Answer a handler made with `Event.advanced`, which decides
`preventDefault` and `stopPropagation` per event. The page has to know before
its listener returns, and a command can't promise that: after each batch of
commands, a port waits for the event loop to come round before it hands over
the next. Decoding happens right away, though, so the answer is in what this
reads from the page's reply object: reading `preventDefault` says to prevent
the default, and reading `stopPropagation` says to stop propagation.
-}
answer : { a | preventDefault : Bool, stopPropagation : Bool } -> Decode.Decoder ()
answer handler =
    Decode.map2 (\_ _ -> ())
        (readIf handler.preventDefault "preventDefault")
        (readIf handler.stopPropagation "stopPropagation")


readIf : Bool -> String -> Decode.Decoder ()
readIf yes field =
    if yes then
        Decode.field field (Decode.succeed ())

    else
        Decode.succeed ()


updateWith : Config flags model msg -> msg -> Live model msg -> ( Live model msg, Cmd (Message msg) )
updateWith config msg live =
    let
        ( model, effect ) =
            config.update msg live.model

        ( performed, cmd ) =
            perform config effect { live | model = model }

        ( requested, frameCmd ) =
            requestFrame config performed
    in
    ( requested, Cmd.batch [ cmd, frameCmd ] )


{-| Commands start now, and so does navigation, which the page reports back
as a change of address. Everything else waits for the next frame: patcher
instructions go out with its patches, and paint messages run around it.
-}
perform : Config flags model msg -> Effect msg -> Live model msg -> ( Live model msg, Cmd (Message msg) )
perform config (Effect.Effect items) live =
    let
        ( performed, cmds, needsFrame ) =
            List.foldl
                (\item ( acc, cs, frame ) ->
                    case item of
                        Command cmd ->
                            ( acc, Cmd.map Got cmd :: cs, frame )

                        Navigate instruction ->
                            ( acc, send config "navigate" instruction :: cs, frame )

                        Client instruction ->
                            ( { acc | instructions = instruction :: acc.instructions }, cs, True )

                        BeforePaint msg ->
                            ( { acc | beforePaint = msg :: acc.beforePaint }, cs, True )

                        AfterPaint msg ->
                            ( { acc | afterPaint = msg :: acc.afterPaint }, cs, True )
                )
                ( live, [], False )
                items
    in
    if needsFrame then
        requestFrame config performed
            |> Tuple.mapSecond (\frameCmd -> Cmd.batch (frameCmd :: List.reverse cmds))

    else
        ( performed, Cmd.batch (List.reverse cmds) )


requestFrame : Config flags model msg -> Live model msg -> ( Live model msg, Cmd (Message msg) )
requestFrame config live =
    if live.frameRequested then
        ( live, Cmd.none )

    else
        ( { live | frameRequested = True }, send config "frame" (Encode.bool True) )


{-| Run the messages waiting for this frame, then diff once and send the
patches and instructions together, with the title if it changed. Messages
that ask for another `beforePaint` get the next frame, so a loop of them
can't starve the page.
-}
render : Config flags model msg -> Live model msg -> ( Live model msg, Cmd (Message msg) )
render config live =
    let
        ( ready, beforeCmds ) =
            List.foldr (\msg acc -> andThen (updateWith config msg) acc)
                ( { live | beforePaint = [], frameRequested = True }, Cmd.none )
                live.beforePaint

        view =
            config.view ready.model

        ( patches, next ) =
            Jorn.Internal.Patch.diffKeeping ready.screen view.body

        instructions =
            List.reverse ready.instructions

        title =
            if view.title /= ready.title then
                Maybe.map (\changed -> ( "title", Encode.string changed )) view.title

            else
                Nothing

        painted =
            { ready
                | screen = next
                , title = view.title
                , instructions = []
                , afterPaint = []
                , painting = ready.painting ++ List.reverse ready.afterPaint
                , frameRequested = False
            }

        sendCmd =
            if List.isEmpty patches && List.isEmpty instructions && List.isEmpty ready.afterPaint && title == Nothing then
                Cmd.none

            else
                config.ports.toJorn
                    (Encode.object
                        ([ ( "patches", Jorn.Patch.encode patches )
                         , ( "instructions", Encode.list identity instructions )
                         , ( "painted", Encode.bool (not (List.isEmpty ready.afterPaint)) )
                         ]
                            ++ List.filterMap identity [ title ]
                        )
                    )

        ( after, nextFrame ) =
            if List.isEmpty ready.beforePaint then
                ( painted, Cmd.none )

            else
                requestFrame config painted
    in
    ( after, Cmd.batch [ beforeCmds, sendCmd, nextFrame ] )


andThen : (Live model msg -> ( Live model msg, Cmd (Message msg) )) -> ( Live model msg, Cmd (Message msg) ) -> ( Live model msg, Cmd (Message msg) )
andThen f ( live, cmd ) =
    let
        ( next, more ) =
            f live
    in
    ( next, Cmd.batch [ cmd, more ] )


send : Config flags model msg -> String -> Value -> Cmd (Message msg)
send config kind payload =
    config.ports.toJorn (Encode.object [ ( kind, payload ) ])
