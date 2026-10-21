port module MemoSpec exposing (main)

{-| A list of memoized rows for client/test/memo.mjs, which counts how often
each row is built. Building a row logs it, so the test can count.
-}

import Jorn
import Jorn.Attribute as Attr
import Jorn.Effect as Effect
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Element.Keyed as Keyed
import Jorn.Event as Event
import Json.Encode as Encode exposing (Value)


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


type alias Row =
    { id : Int
    , label : String
    }


type alias Model =
    { rows : List Row
    , count : Int
    }


type Msg
    = Count
    | Rename Int
    | Reverse


main : Jorn.Program () Model Msg
main =
    Jorn.application
        { init = \_ -> ( { rows = List.map (\id -> { id = id, label = "row " ++ String.fromInt id }) (List.range 1 100), count = 0 }, Effect.none )
        , update = \msg model -> ( update msg model, Effect.none )
        , view = view
        , subscriptions = \_ -> Sub.none
        , ports = { toJorn = toJorn, fromJorn = fromJorn }
        }


update : Msg -> Model -> Model
update msg model =
    case msg of
        Count ->
            { model | count = model.count + 1 }

        Rename id ->
            { model
                | rows =
                    List.map
                        (\row ->
                            if row.id == id then
                                { row | label = row.label ++ "!" }

                            else
                                row
                        )
                        model.rows
            }

        Reverse ->
            { model | rows = List.reverse model.rows }


view : Model -> Element Msg
view model =
    Html.div []
        [ Html.button [ Attr.id "count", Event.onClick Count ] [ Element.text (String.fromInt model.count) ]
        , Html.button [ Attr.id "reverse", Event.onClick Reverse ] []
        , Keyed.ul [ Attr.id "rows" ] (List.map (\row -> ( String.fromInt row.id, viewRow row )) model.rows)
        ]


viewRow : Row -> Element Msg
viewRow row =
    Element.memo [ Encode.int row.id, Encode.string row.label ]
        (\() ->
            let
                _ =
                    Debug.log "built" row.id
            in
            Html.li []
                [ Html.button [ Attr.id ("row-" ++ String.fromInt row.id), Event.onClick (Rename row.id) ]
                    [ Element.text row.label ]
                ]
        )
