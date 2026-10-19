module Jorn.Effect exposing
    ( Effect
    , none, batch, map
    , fromCmd
    , focus, blur, scrollIntoView
    , beforePaint, afterPaint
    , event, client
    )

{-| Effects as values. `update` returns a description of what should happen,
and the runtime makes it happen, so `update` stays pure and testable.

    update : Msg -> Model -> ( Model, Effect Msg )
    update msg model =
        case msg of
            StartEditing ->
                ( { model | editing = True }, Effect.focus "title-input" )

            Save ->
                ( model, Effect.fromCmd (Http.post { ... }) )


## What runs where

An Elm package can't run arbitrary JavaScript, so there are three kinds of
effect:

  - **Elm commands**, through `fromCmd`. HTTP, time, random and the rest of
    the platform run in the Elm program, wherever it runs.
  - **Patcher instructions**: `focus`, `blur`, `scrollIntoView`, `event` and
    `client`. They go to `client/jorn.js` with the next batch of patches and
    run right after the patches are applied, so they can refer to elements the
    same update created.
  - **Paint timing**: `beforePaint` and `afterPaint` send your `update` a
    message around the next render.

In client mode all three run in the browser. In server mode, commands and
paint timing run on the server, and patcher instructions go to the page over
the socket. Commands then use the server's clock, time zone and network, so
HTTP requests need absolute URLs and carry no cookies.


# Effects

@docs Effect


# Combining

@docs none, batch, map


# Elm commands

@docs fromCmd


# Focus and scrolling

Each takes an element's `id`.

@docs focus, blur, scrollIntoView


# Paint timing

@docs beforePaint, afterPaint


# Talking to the page

@docs event, client

-}

import Jorn.Internal.Effect as Internal exposing (Item(..))
import Json.Encode as Encode exposing (Value)


{-| Something for the runtime to do, which may send a `msg` back to
`update`.
-}
type alias Effect msg =
    Internal.Effect msg


{-| Do nothing.
-}
none : Effect msg
none =
    Internal.Effect []


{-| Do several things. They start in order; commands may finish in any order.
-}
batch : List (Effect msg) -> Effect msg
batch effects =
    Internal.Effect (List.concatMap (\(Internal.Effect items) -> items) effects)


{-| Transform the messages an effect sends back, for nested components.
-}
map : (a -> b) -> Effect a -> Effect b
map =
    Internal.map


{-| Run an ordinary Elm command, such as an HTTP request.
-}
fromCmd : Cmd msg -> Effect msg
fromCmd cmd =
    Internal.Effect [ Command cmd ]


{-| Focus the element with this `id`, once the DOM has caught up with the
update that asked for it.
-}
focus : String -> Effect msg
focus id =
    instruction "focus" [ ( "id", Encode.string id ) ]


{-| Take focus away from the element with this `id`.
-}
blur : String -> Effect msg
blur id =
    instruction "blur" [ ( "id", Encode.string id ) ]


{-| Scroll the element with this `id` into view.
-}
scrollIntoView : String -> Effect msg
scrollIntoView id =
    instruction "scroll-into-view" [ ( "id", Encode.string id ) ]


{-| Send `update` this message just before the next render: after the
current batch of messages, and before the view is diffed. Good for measuring
or settling state the view depends on.
-}
beforePaint : msg -> Effect msg
beforePaint msg =
    Internal.Effect [ BeforePaint msg ]


{-| Send `update` this message once the next render's patches and patcher
instructions have been applied to the DOM.
-}
afterPaint : msg -> Effect msg
afterPaint msg =
    Internal.Effect [ AfterPaint msg ]


{-| Dispatch a DOM `CustomEvent` with this name and `detail` from the element
the app is mounted in. It bubbles, and crosses shadow DOM boundaries, so the
page around your app can listen for it:

    Effect.event "saved" (Encode.object [ ( "id", Encode.string id ) ])

-}
event : String -> Value -> Effect msg
event name detail =
    instruction "event" [ ( "name", Encode.string name ), ( "detail", detail ) ]


{-| Run a JavaScript function the page registered with `start` in
`client/jorn.js`, passing it this payload:

    -- Elm
    Effect.client "copy" (Encode.string model.link)

    // JavaScript
    start(Elm.Main, container, {
      effects: { copy: (text) => navigator.clipboard.writeText(text) },
    });

This is how to reach browser APIs that Elm doesn't cover. To get a result
back, have the function send it into one of your own ports.

-}
client : String -> Value -> Effect msg
client name payload =
    instruction "client" [ ( "name", Encode.string name ), ( "payload", payload ) ]


instruction : String -> List ( String, Value ) -> Effect msg
instruction kind fields =
    Internal.Effect [ Client (Encode.object (( "effect", Encode.string kind ) :: fields)) ]
