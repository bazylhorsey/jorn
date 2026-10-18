module Jorn.Internal.Effect exposing (Effect(..), Item(..), map)

{-| Effects as plain data, so `update` stays pure and the runtime decides
where each one runs.

`Client` instructions go to the patcher with the next batch of patches, as
JSON, because they have to happen after the DOM has caught up: focusing an
input only works once the input exists.

-}

import Json.Encode exposing (Value)


type Effect msg
    = Effect (List (Item msg))


type Item msg
    = Command (Cmd msg)
    | Client Value
    | BeforePaint msg
    | AfterPaint msg


map : (a -> b) -> Effect a -> Effect b
map f (Effect items) =
    Effect (List.map (mapItem f) items)


mapItem : (a -> b) -> Item a -> Item b
mapItem f item =
    case item of
        Command cmd ->
            Command (Cmd.map f cmd)

        Client instruction ->
            Client instruction

        BeforePaint msg ->
            BeforePaint (f msg)

        AfterPaint msg ->
            AfterPaint (f msg)
