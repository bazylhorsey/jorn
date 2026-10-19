module Jorn.ServerComponent exposing
    ( element, route, flags, csrfToken, script
    , decodeEvent, Error(..), errorToString
    )

{-| Put a server component in a page, and the pieces for hosting one
yourself.

A server component is a Jorn program running on a server with `attach` from
`server/jorn.js`. `element` makes the tag that shows it:

    ServerComponent.element
        [ ServerComponent.route "/chat"
        , Event.on "message-sent" messageSent
        ]

The tag is `<jorn-server-component>`, which `defineServerComponent` in
`client/jorn.js` defines. It connects when it's added to the page and
disconnects when it's removed. Moving it, for example in a keyed list, keeps
the connection.

The component talks to the page around it with `Effect.event`, which
dispatches a DOM event from this element. Listen for it with `Event.on`, as
above.


# Embedding

@docs element, route, flags, csrfToken, script


# Hosting

`server/jorn.js` does this for you. These are for hosts that run a Jorn view
and move its messages themselves. [PROTOCOL.md](https://github.com/bazylhorsey/jorn/blob/main/PROTOCOL.md)
has the messages, and `Jorn.Patch` encodes what goes to the page.

@docs decodeEvent, Error, errorToString

-}

import Jorn.Attribute as Attribute exposing (Attribute)
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Internal.Event as Routing
import Json.Decode as Decode exposing (Value)
import Json.Encode as Encode


{-| The element that shows a server component. Its contents come from the
server, so it takes no children.
-}
element : List (Attribute msg) -> Element msg
element attributes =
    Element.element "jorn-server-component" attributes []


{-| Where the component's socket is, like `"/chat"`. A relative address is
resolved against the page's.
-}
route : String -> Attribute msg
route =
    Attribute.attribute "route"


{-| Flags to send the server when the component connects. The server's
`flags` function decides whether to use them, since a page can send anything.
-}
flags : Value -> Attribute msg
flags value =
    Attribute.attribute "flags" (Encode.encode 0 value)


{-| A token for the server's `authorize` function to check before it starts
a session, for when the origin check isn't enough.
-}
csrfToken : String -> Attribute msg
csrfToken =
    Attribute.attribute "csrf-token"


{-| A script that loads `client/jorn.js` from the given address and defines
`<jorn-server-component>`, for pages that don't load it already. A page that
starts a Jorn app with `start` can call `defineServerComponent` itself
instead, which is also how to give components `Effect.client` functions.
-}
script : String -> Element msg
script address =
    Html.script [ Attribute.type_ "module" ]
        [ Element.text
            ("import { defineServerComponent } from "
                ++ String.replace "<" "\\u003C" (Encode.encode 0 (Encode.string address))
                ++ ";\ndefineServerComponent();"
            )
        ]



-- HOSTING


{-| Turn an event the page reported, `{"path": [...], "name": "...",
"event": {...}}`, into a message, by finding the handler that produced it
in the view that's on the page.
-}
decodeEvent : Element msg -> Value -> Result Error msg
decodeEvent view value =
    case Decode.decodeValue Routing.decoder value of
        Err problem ->
            Err (NotAnEvent problem)

        Ok incoming ->
            case Routing.route incoming view of
                Ok msg ->
                    Ok msg

                Err (Routing.NodeNotFound path) ->
                    Err (NodeNotFound path)

                Err (Routing.NoHandler path name) ->
                    Err (NoHandler path name)

                Err (Routing.DecodeFailed name problem) ->
                    Err (HandlerFailed name problem)


{-| Why an event didn't become a message: it wasn't an event, nothing is at
its path, nothing there handles it, or the handler's decoder failed. The
last three usually mean the page and the server are looking at different
views.
-}
type Error
    = NotAnEvent Decode.Error
    | NodeNotFound (List Int)
    | NoHandler (List Int) String
    | HandlerFailed String Decode.Error


{-| A description for logs.
-}
errorToString : Error -> String
errorToString error =
    case error of
        NotAnEvent problem ->
            "Not an event: " ++ Decode.errorToString problem

        NodeNotFound path ->
            Routing.errorToString (Routing.NodeNotFound path)

        NoHandler path name ->
            Routing.errorToString (Routing.NoHandler path name)

        HandlerFailed name problem ->
            Routing.errorToString (Routing.DecodeFailed name problem)
