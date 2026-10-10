module Jorn.Event exposing
    ( Incoming, decoder
    , route, Error(..), errorToString
    )

{-| Route an event reported by the client back to the handler that produced it.

    case Decode.decodeValue Jorn.Event.decoder raw of
        Ok incoming ->
            Jorn.Event.route incoming currentView

        Err _ ->
            ...

Always route against the tree the client is currently displaying.


# Incoming events

@docs Incoming, decoder


# Routing

@docs route, Error, errorToString

-}

import Dict
import Jorn.Html exposing (Html)
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
route : Incoming -> Html msg -> Result Error msg
route incoming html =
    case find incoming.path html of
        Nothing ->
            Err (NodeNotFound incoming.path)

        Just (Vdom.Text _) ->
            Err (NoHandler incoming.path incoming.name)

        Just (Vdom.Element _ _ attributes _) ->
            case Dict.get incoming.name (Vdom.facts attributes).events of
                Nothing ->
                    Err (NoHandler incoming.path incoming.name)

                Just ( _, handler ) ->
                    Decode.decodeValue handler incoming.event
                        |> Result.mapError (DecodeFailed incoming.name)


find : List Int -> Html msg -> Maybe (Html msg)
find path html =
    case path of
        [] ->
            Just html

        index :: rest ->
            case html of
                Vdom.Element _ _ _ children ->
                    if index < 0 then
                        Nothing

                    else
                        children
                            |> List.drop index
                            |> List.head
                            |> Maybe.andThen (find rest)

                Vdom.Text _ ->
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
