module Jorn.Internal.Event exposing
    ( Incoming, decoder
    , route, decide, Error(..), errorToString
    )

{-| Route an event reported by the client back to the handler that produced it.

The runtime routes with this, and `Jorn.ServerComponent.decodeEvent` is the
public face of it.


# Incoming events

@docs Incoming, decoder


# Routing

@docs route, decide, Error, errorToString

-}

import Dict
import Jorn.Element exposing (Element)
import Jorn.Internal.Vdom as Vdom
import Json.Decode as Decode exposing (Decoder, Value)


{-| An event as reported by the client: where it fired, its name, and the
serialized event fields.
-}
type alias Incoming =
    { path : List Int
    , name : String
    , event : Value
    }


{-| Decodes `{"path": [...], "name": "...", "event": {...}}`.
-}
decoder : Decoder Incoming
decoder =
    Decode.map3 Incoming
        (Decode.field "path" (Decode.list Decode.int))
        (Decode.field "name" Decode.string)
        (Decode.field "event" Decode.value)


{-| Why an event couldn't be turned into a message.
-}
type Error
    = NodeNotFound (List Int)
    | NoHandler (List Int) String
    | DecodeFailed String Decode.Error


{-| Find the handler at the event's path and run its decoder on the payload.
-}
route : Incoming -> Element msg -> Result Error msg
route incoming element =
    decide incoming element
        |> Result.map .message


{-| Like `route`, with the rest of the handler's answer: whether it asks to
prevent the event's default and stop its propagation. Only handlers made with
`Event.advanced` ever ask.
-}
decide : Incoming -> Element msg -> Result Error (Vdom.Handler msg)
decide incoming element =
    case find incoming.path (Vdom.root element) of
        Nothing ->
            Err (NodeNotFound incoming.path)

        Just (Vdom.Element _ _ _ attributes _) ->
            handle incoming attributes

        Just (Vdom.Raw _ _ attributes _) ->
            handle incoming attributes

        Just _ ->
            Err (NoHandler incoming.path incoming.name)


handle : Incoming -> List (Vdom.Attribute msg) -> Result Error (Vdom.Handler msg)
handle incoming attributes =
    case Dict.get incoming.name (Vdom.facts attributes).events of
        Nothing ->
            Err (NoHandler incoming.path incoming.name)

        Just ( _, handler ) ->
            Decode.decodeValue handler incoming.event
                |> Result.mapError (DecodeFailed incoming.name)


find : List Int -> Element msg -> Maybe (Element msg)
find path element =
    case path of
        [] ->
            Just element

        index :: rest ->
            case element of
                Vdom.Element _ _ _ _ children ->
                    if index < 0 then
                        Nothing

                    else
                        Vdom.flatten children
                            |> List.drop index
                            |> List.head
                            |> Maybe.map Vdom.unkey
                            |> Maybe.andThen (find rest)

                _ ->
                    Nothing


{-| A readable description, for logs.
-}
errorToString : Error -> String
errorToString error =
    case error of
        NodeNotFound path ->
            "No node at path " ++ pathToString path

        NoHandler path name ->
            "No \"" ++ name ++ "\" handler at path " ++ pathToString path

        DecodeFailed name decodeError ->
            "The \"" ++ name ++ "\" handler failed to decode: " ++ Decode.errorToString decodeError


pathToString : List Int -> String
pathToString path =
    "[" ++ String.join "," (List.map String.fromInt path) ++ "]"
