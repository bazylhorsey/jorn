module Jorn exposing
    ( Program, Ports
    , simple, application
    , State, Message
    )

{-| Run a Jorn app. Jorn provides the loop every app needs: mount the view,
route each event to its handler, call `update`, diff, and send the patches
to `client/jorn.js`.

An Elm package can't declare ports, so your app declares two and hands them
over. That's the only glue:

    port module Main exposing (main)

    import Jorn
    import Json.Encode exposing (Value)

    port toJorn : Value -> Cmd msg

    port fromJorn : (Value -> msg) -> Sub msg

    main : Jorn.Program () Model Msg
    main =
        Jorn.simple
            { init = init
            , update = update
            , view = view
            , ports = { toJorn = toJorn, fromJorn = fromJorn }
            }

On the page, `start` from `client/jorn.js` connects the compiled program to
an element:

    import { start } from "./jorn.js";

    start(Elm.Main, document.getElementById("app"));

The same program can run on a server instead, with `attach` from
`server/jorn.js` on Node and `stream` from `client/jorn.js` in the page.
Nothing in your Elm code changes: `update`, `view` and commands run on the
server, and focus, scrolling and `Effect.client` run in the page.


# Programs

@docs Program, Ports


# Starting

@docs simple, application


# Internals

@docs State, Message

-}

import Jorn.Effect exposing (Effect)
import Jorn.Element exposing (Element)
import Jorn.Internal.Effect as Effect exposing (Item(..))
import Jorn.Internal.Event as Routing
import Jorn.Internal.Patch
import Jorn.Internal.Vdom as Vdom
import Jorn.Patch
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)


{-| A Jorn app, ready to be your `main`.
-}
type alias Program flags model msg =
    Platform.Program flags (State model msg) (Message msg)


{-| The two ports your app declares, named `toJorn` and `fromJorn`:

    port toJorn : Value -> Cmd msg

    port fromJorn : (Value -> msg) -> Sub msg

`start` looks for those names. If yours differ, tell it with the `ports`
option.

-}
type alias Ports msg =
    { toJorn : Value -> Cmd (Message msg)
    , fromJorn : (Value -> Message msg) -> Sub (Message msg)
    }


{-| The runtime's own model, which wraps yours. You never build one.
-}
type State model msg
    = State
        { model : model
        , screen : Element msg
        , frameRequested : Bool
        , beforePaint : List msg
        , afterPaint : List msg
        , painting : List msg
        , instructions : List Value
        , running : Bool
        }


{-| The runtime's own message type, which wraps yours. You never build one.
-}
type Message msg
    = FromClient Value
    | Got msg


{-| An app with no effects: `init` is the first model and `update` returns
the next one.
-}
simple :
    { init : model
    , update : msg -> model -> model
    , view : model -> Element msg
    , ports : Ports msg
    }
    -> Program () model msg
simple config =
    application
        { init = \_ -> ( config.init, Jorn.Effect.none )
        , update = \msg model -> ( config.update msg model, Jorn.Effect.none )
        , view = config.view
        , subscriptions = \_ -> Sub.none
        , ports = config.ports
        }


{-| An app whose `init` and `update` return effects, and which can subscribe
to anything Elm offers, such as time or its own ports.

Messages are batched: however many arrive before the next animation frame,
the view is diffed once and the patches go out together.

-}
application :
    { init : flags -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : model -> Element msg
    , subscriptions : model -> Sub msg
    , ports : Ports msg
    }
    -> Program flags model msg
application config =
    Platform.worker
        { init = \flags -> start config flags
        , update = step config
        , subscriptions =
            \(State state) ->
                if state.running then
                    Sub.batch [ config.ports.fromJorn FromClient, Sub.map Got (config.subscriptions state.model) ]

                else
                    Sub.none
        }


type alias Config flags model msg =
    { init : flags -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : model -> Element msg
    , subscriptions : model -> Sub msg
    , ports : Ports msg
    }


start : Config flags model msg -> flags -> ( State model msg, Cmd (Message msg) )
start config flags =
    let
        ( model, effect ) =
            config.init flags

        view =
            config.view model

        -- Memos keep what they build, so events and the next diff don't
        -- build them again.
        screen =
            Maybe.withDefault view (Vdom.build view)

        initial =
            State
                { model = model
                , screen = screen
                , frameRequested = False
                , beforePaint = []
                , afterPaint = []
                , painting = []
                , instructions = []
                , running = True
                }

        ( state, cmd ) =
            perform config effect initial
    in
    ( state
    , Cmd.batch [ send config "mount" (Jorn.Patch.encodeHtml screen), cmd ]
    )


step : Config flags model msg -> Message msg -> State model msg -> ( State model msg, Cmd (Message msg) )
step config message ((State s) as state) =
    if not s.running then
        ( state, Cmd.none )

    else
        case message of
            Got msg ->
                updateWith config msg state

            FromClient value ->
                case Decode.decodeValue incoming value of
                    Ok (Event event) ->
                        case Routing.route event s.screen of
                            Ok msg ->
                                updateWith config msg state

                            Err problem ->
                                ( state, send config "error" (Encode.string (Routing.errorToString problem)) )

                    Ok (Decide event reply) ->
                        case Routing.decide event s.screen of
                            Ok handler ->
                                -- Reading `reply` is the answer, so what
                                -- decoding it returns doesn't matter.
                                case Decode.decodeValue (answer handler) reply of
                                    Ok () ->
                                        ( state, Cmd.none )

                                    Err _ ->
                                        ( state, Cmd.none )

                            Err _ ->
                                ( state, Cmd.none )

                    Ok Frame ->
                        render config state

                    Ok Painted ->
                        List.foldl (\msg acc -> andThen (updateWith config msg) acc) ( State { s | painting = [] }, Cmd.none ) s.painting

                    Ok Remount ->
                        ( state
                        , config.ports.toJorn
                            (Encode.object
                                [ ( "mount", Jorn.Patch.encodeHtml s.screen )
                                , ( "painted", Encode.bool (not (List.isEmpty s.painting)) )
                                ]
                            )
                        )

                    Ok Shutdown ->
                        ( State { s | running = False }, Cmd.none )

                    Err problem ->
                        ( state, send config "error" (Encode.string (Decode.errorToString problem)) )


{-| What the page sends: an event, a question about an event that's still
firing, the animation frame we asked for, word that the last patches are on
the page, a request for the whole view because the page lost track of it, or
a request to stop.

The question comes with a reply object to answer on (see `answer`). Nothing
else happens: the event itself follows as an ordinary `Event`.

-}
type Incoming
    = Event Routing.Incoming
    | Decide Routing.Incoming Value
    | Frame
    | Painted
    | Remount
    | Shutdown


incoming : Decode.Decoder Incoming
incoming =
    Decode.oneOf
        [ Decode.field "event" (Decode.map Event Routing.decoder)
        , Decode.map2 Decide (Decode.field "decide" Routing.decoder) (Decode.field "reply" Decode.value)
        , Decode.field "frame" (Decode.succeed Frame)
        , Decode.field "painted" (Decode.succeed Painted)
        , Decode.field "remount" (Decode.succeed Remount)
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


updateWith : Config flags model msg -> msg -> State model msg -> ( State model msg, Cmd (Message msg) )
updateWith config msg (State s) =
    let
        ( model, effect ) =
            config.update msg s.model

        ( state, cmd ) =
            perform config effect (State { s | model = model })

        ( requested, frameCmd ) =
            requestFrame config state
    in
    ( requested, Cmd.batch [ cmd, frameCmd ] )


{-| Commands start now. Everything else waits for the next frame: patcher
instructions go out with its patches, and paint messages run around it.
-}
perform : Config flags model msg -> Effect msg -> State model msg -> ( State model msg, Cmd (Message msg) )
perform config (Effect.Effect items) state =
    let
        ( State s, cmds, needsFrame ) =
            List.foldl
                (\item ( State acc, cs, frame ) ->
                    case item of
                        Command cmd ->
                            ( State acc, Cmd.map Got cmd :: cs, frame )

                        Client instruction ->
                            ( State { acc | instructions = instruction :: acc.instructions }, cs, True )

                        BeforePaint msg ->
                            ( State { acc | beforePaint = msg :: acc.beforePaint }, cs, True )

                        AfterPaint msg ->
                            ( State { acc | afterPaint = msg :: acc.afterPaint }, cs, True )
                )
                ( state, [], False )
                items
    in
    if needsFrame then
        requestFrame config (State s)
            |> Tuple.mapSecond (\frameCmd -> Cmd.batch (frameCmd :: List.reverse cmds))

    else
        ( State s, Cmd.batch (List.reverse cmds) )


requestFrame : Config flags model msg -> State model msg -> ( State model msg, Cmd (Message msg) )
requestFrame config (State s) =
    if s.frameRequested then
        ( State s, Cmd.none )

    else
        ( State { s | frameRequested = True }, send config "frame" (Encode.bool True) )


{-| Run the messages waiting for this frame, then diff once and send the
patches and instructions together. Messages that ask for another
`beforePaint` get the next frame, so a loop of them can't starve the page.
-}
render : Config flags model msg -> State model msg -> ( State model msg, Cmd (Message msg) )
render config (State s) =
    let
        ( State ready, beforeCmds ) =
            List.foldr (\msg acc -> andThen (updateWith config msg) acc)
                ( State { s | beforePaint = [], frameRequested = True }, Cmd.none )
                s.beforePaint

        ( patches, next ) =
            Jorn.Internal.Patch.diffKeeping ready.screen (config.view ready.model)

        instructions =
            List.reverse ready.instructions

        painted =
            State
                { ready
                    | screen = next
                    , instructions = []
                    , afterPaint = []
                    , painting = ready.painting ++ List.reverse ready.afterPaint
                    , frameRequested = False
                }

        sendCmd =
            if List.isEmpty patches && List.isEmpty instructions && List.isEmpty ready.afterPaint then
                Cmd.none

            else
                config.ports.toJorn
                    (Encode.object
                        [ ( "patches", Jorn.Patch.encode patches )
                        , ( "instructions", Encode.list identity instructions )
                        , ( "painted", Encode.bool (not (List.isEmpty ready.afterPaint)) )
                        ]
                    )

        ( after, nextFrame ) =
            if List.isEmpty ready.beforePaint then
                ( painted, Cmd.none )

            else
                requestFrame config painted
    in
    ( after, Cmd.batch [ beforeCmds, sendCmd, nextFrame ] )


andThen : (State model msg -> ( State model msg, Cmd (Message msg) )) -> ( State model msg, Cmd (Message msg) ) -> ( State model msg, Cmd (Message msg) )
andThen f ( state, cmd ) =
    let
        ( next, more ) =
            f state
    in
    ( next, Cmd.batch [ cmd, more ] )


send : Config flags model msg -> String -> Value -> Cmd (Message msg)
send config kind payload =
    config.ports.toJorn (Encode.object [ ( kind, payload ) ])
