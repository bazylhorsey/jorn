module Jorn exposing
    ( Program, Ports
    , simple, application, resumable
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

@docs simple, application, resumable


# Internals

@docs State, Message

-}

import Jorn.Effect exposing (Effect)
import Jorn.Element exposing (Element)
import Jorn.Internal.Effect as Effect exposing (Item(..))
import Jorn.Internal.Event as Routing
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
        , held : Maybe (Effect msg)
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
    program
        { init = config.init
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        , ports = config.ports
        , snapshots = Nothing
        }


{-| An `application` whose sessions survive a restart of the server, for
example a deploy. When `attach` in `server/jorn.js` has somewhere to keep
them, it saves each session's model with `encode` before the server stops.
A page that comes back after the restart gets its model again, read by
`decoder` from the new version of your code, and carries on where it was.

    main : Jorn.Program () Model Msg
    main =
        Jorn.resumable
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            , ports = { toJorn = toJorn, fromJorn = fromJorn }
            , encode = encodeModel
            , decoder = modelDecoder
            }

If `decoder` can't read a saved model, because the model changed in a way it
doesn't handle, the page starts over from `init` and the server logs why.

A session that picks up a saved model doesn't run `init`, so neither do its
effects. Anything that was in flight when the server stopped, like an HTTP
request, is lost, so keep what you'd need to retry in the model.

In the page, a resumable app runs like any other.

-}
resumable :
    { init : flags -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : model -> Element msg
    , subscriptions : model -> Sub msg
    , ports : Ports msg
    , encode : model -> Value
    , decoder : Decode.Decoder model
    }
    -> Program flags model msg
resumable config =
    program
        { init = config.init
        , update = config.update
        , view = config.view
        , subscriptions = config.subscriptions
        , ports = config.ports
        , snapshots = Just { encode = config.encode, decoder = config.decoder }
        }


program : Config flags model msg -> Program flags model msg
program config =
    Platform.worker
        { init = \flags -> start config flags
        , update = step config
        , subscriptions =
            \(State state) ->
                case ( state.running, state.held ) of
                    ( False, _ ) ->
                        Sub.none

                    ( True, Just _ ) ->
                        -- Nothing of the app's runs until it's started.
                        config.ports.fromJorn FromClient

                    ( True, Nothing ) ->
                        Sub.batch [ config.ports.fromJorn FromClient, Sub.map Got (config.subscriptions state.model) ]
        }


type alias Config flags model msg =
    { init : flags -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : model -> Element msg
    , subscriptions : model -> Sub msg
    , ports : Ports msg
    , snapshots : Maybe { encode : model -> Value, decoder : Decode.Decoder model }
    }


start : Config flags model msg -> flags -> ( State model msg, Cmd (Message msg) )
start config flags =
    let
        ( model, effect ) =
            config.init flags

        screen =
            config.view model

        initial =
            { model = model
            , screen = screen
            , frameRequested = False
            , beforePaint = []
            , afterPaint = []
            , painting = []
            , instructions = []
            , running = True
            , held = Nothing
            }
    in
    case config.snapshots of
        Nothing ->
            mount config effect (State initial)

        Just _ ->
            -- The host says whether this is a fresh start or a saved session,
            -- and until then `init`'s effects wait.
            ( State { initial | held = Just effect }, send config "ready" (Encode.bool True) )


{-| Show the view and start the effects.
-}
mount : Config flags model msg -> Effect msg -> State model msg -> ( State model msg, Cmd (Message msg) )
mount config effect ((State s) as state) =
    let
        ( next, cmd ) =
            perform config effect state
    in
    ( next
    , Cmd.batch [ send config "mount" (Jorn.Patch.encodeHtml s.screen), cmd ]
    )


step : Config flags model msg -> Message msg -> State model msg -> ( State model msg, Cmd (Message msg) )
step config message ((State s) as state) =
    if not s.running then
        ( state, Cmd.none )

    else
        case ( message, s.held ) of
            ( FromClient value, Just effect ) ->
                case Decode.decodeValue incoming value of
                    Ok Fresh ->
                        mount config effect (State { s | held = Nothing })

                    Ok (Restore saved) ->
                        restore config effect saved (State { s | held = Nothing })

                    Ok Shutdown ->
                        ( State { s | running = False }, Cmd.none )

                    Ok Snapshot ->
                        ( state, send config "snapshot" Encode.null )

                    _ ->
                        -- There's no view on the page yet for anything else.
                        ( state, Cmd.none )

            ( Got _, Just _ ) ->
                ( state, Cmd.none )

            ( Got msg, Nothing ) ->
                updateWith config msg state

            ( FromClient value, Nothing ) ->
                case Decode.decodeValue incoming value of
                    Ok (Event event) ->
                        case Routing.route event s.screen of
                            Ok msg ->
                                updateWith config msg state

                            Err problem ->
                                ( state, send config "error" (Encode.string (Routing.errorToString problem)) )

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

                    Ok Snapshot ->
                        ( state
                        , send config "snapshot" (Maybe.withDefault Encode.null (Maybe.map (\{ encode } -> encode s.model) config.snapshots))
                        )

                    Ok Fresh ->
                        ( state, Cmd.none )

                    Ok (Restore _) ->
                        ( state, Cmd.none )

                    Err problem ->
                        ( state, send config "error" (Encode.string (Decode.errorToString problem)) )


{-| Carry on from a saved model, or start over from `init` if this version's
decoder can't read it.
-}
restore : Config flags model msg -> Effect msg -> Value -> State model msg -> ( State model msg, Cmd (Message msg) )
restore config effect saved ((State s) as state) =
    case Maybe.map (\{ decoder } -> Decode.decodeValue decoder saved) config.snapshots of
        Just (Ok model) ->
            mount config Jorn.Effect.none (State { s | model = model, screen = config.view model })

        Just (Err problem) ->
            mount config effect state
                |> Tuple.mapSecond
                    (\cmd ->
                        Cmd.batch
                            [ send config "error" (Encode.string ("Couldn't read the saved session, so it started over. " ++ describe "" problem))
                            , cmd
                            ]
                    )

        Nothing ->
            mount config effect state


{-| Where a decoder failed and why, leaving out the value, which could be
large or private.
-}
describe : String -> Decode.Error -> String
describe path problem =
    let
        at =
            if String.isEmpty path then
                ""

            else
                "At " ++ path ++ ": "
    in
    case problem of
        Decode.Field field next ->
            describe (path ++ "." ++ field) next

        Decode.Index index next ->
            describe (path ++ "[" ++ String.fromInt index ++ "]") next

        Decode.OneOf [ only ] ->
            describe path only

        Decode.OneOf problems ->
            at ++ "none of these worked: " ++ String.join " Or: " (List.map (describe "") problems)

        Decode.Failure message _ ->
            at ++ message


{-| What the page sends: an event, the animation frame we asked for, word
that the last patches are on the page, a request for the whole view because
the page lost track of it, or a request to stop. A resumable program also
hears whether to start fresh or from a saved model, and requests for its
model to save.
-}
type Incoming
    = Event Routing.Incoming
    | Frame
    | Painted
    | Remount
    | Shutdown
    | Fresh
    | Restore Value
    | Snapshot


incoming : Decode.Decoder Incoming
incoming =
    Decode.oneOf
        [ Decode.field "event" (Decode.map Event Routing.decoder)
        , Decode.field "frame" (Decode.succeed Frame)
        , Decode.field "painted" (Decode.succeed Painted)
        , Decode.field "remount" (Decode.succeed Remount)
        , Decode.field "shutdown" (Decode.succeed Shutdown)
        , Decode.field "fresh" (Decode.succeed Fresh)
        , Decode.field "restore" (Decode.map Restore Decode.value)
        , Decode.field "snapshot" (Decode.succeed Snapshot)
        ]


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

        next =
            config.view ready.model

        patches =
            Jorn.Patch.diff ready.screen next

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
