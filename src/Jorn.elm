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

Any other ports your app declares are its own, for the JavaScript around it.
`start` returns them, as `Elm.Main.init` would, and on a server `attach`
hands each session's ports to your server code, so a message can reach a
running app from outside it.

For an app that owns the page's address, with links and the back button
handled in Elm, see `Jorn.Navigation`.


# Programs

@docs Program, Ports


# Starting

@docs simple, application


# Internals

@docs State, Message

-}

import Jorn.Effect exposing (Effect)
import Jorn.Element exposing (Element)
import Jorn.Internal.Runtime as Runtime
import Json.Encode exposing (Value)


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
type alias State model msg =
    Runtime.State model msg


{-| The runtime's own message type, which wraps yours. You never build one.
-}
type alias Message msg =
    Runtime.Message msg


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
    Runtime.program
        { init = \flags -> Runtime.Now (config.init flags)
        , update = config.update
        , view = \model -> { title = Nothing, body = config.view model }
        , subscriptions = config.subscriptions
        , ports = config.ports
        , routing = Nothing
        }
