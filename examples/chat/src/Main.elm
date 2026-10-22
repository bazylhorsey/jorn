port module Main exposing (main)

{-| A chat room. Each page gets its own session of this program on the
server, and the sessions never see each other: server code in `chat.mjs`
passes what one says to all of them, through two ports of the program's own.
-}

import Jorn
import Jorn.Attribute as Attr
import Jorn.Effect as Effect exposing (Effect)
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Element.Keyed as Keyed
import Jorn.Event as Event
import Json.Decode as Decode exposing (Decoder)
import Json.Encode exposing (Value)


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


{-| This page's person said something. Server code passes it on to everyone.
-}
port say : String -> Cmd msg


{-| A line for the room, from server code: someone said something, or came
or went.
-}
port hear : (Value -> msg) -> Sub msg


main : Jorn.Program Value Model Msg
main =
    Jorn.application
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> hear Heard
        , ports = { toJorn = toJorn, fromJorn = fromJorn }
        }



-- MODEL


type alias Model =
    { name : String
    , lines : List ( Int, Line )
    , heard : Int
    , draft : String
    }


type Line
    = Said String String
    | Joined String
    | Left String


{-| Server code picks the name and sends the room's recent lines, so a page
that joins late sees what it missed.
-}
init : Value -> ( Model, Effect Msg )
init flags =
    let
        decoded =
            Decode.decodeValue
                (Decode.map2 Tuple.pair
                    (Decode.field "name" Decode.string)
                    (Decode.field "recent" (Decode.list lineDecoder))
                )
                flags

        ( name, recent ) =
            Result.withDefault ( "Guest", [] ) decoded
    in
    ( List.foldl addLine { name = name, lines = [], heard = 0, draft = "" } recent
    , Effect.none
    )


lineDecoder : Decoder Line
lineDecoder =
    Decode.field "name" Decode.string
        |> Decode.andThen
            (\name ->
                Decode.oneOf
                    [ Decode.field "text" (Decode.map (Said name) Decode.string)
                    , Decode.field "joined" (Decode.succeed (Joined name))
                    , Decode.field "left" (Decode.succeed (Left name))
                    ]
            )


{-| Keep the last hundred lines. Each gets a number, its key in the list, so
dropping the oldest moves nothing else.
-}
addLine : Line -> Model -> Model
addLine line model =
    { model
        | lines = List.drop (List.length model.lines - 99) model.lines ++ [ ( model.heard, line ) ]
        , heard = model.heard + 1
    }



-- UPDATE


type Msg
    = Typed String
    | Send
    | Heard Value


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        Typed draft ->
            ( { model | draft = draft }, Effect.none )

        Send ->
            if String.isEmpty (String.trim model.draft) then
                ( model, Effect.none )

            else
                -- Not added here: it comes back through `hear` like
                -- everyone else's, so every page shows the same order.
                ( { model | draft = "" }, Effect.fromCmd (say (String.trim model.draft)) )

        Heard value ->
            case Decode.decodeValue lineDecoder value of
                Ok line ->
                    ( addLine line model, Effect.none )

                Err _ ->
                    ( model, Effect.none )



-- VIEW


view : Model -> Element Msg
view model =
    Html.main_ []
        [ Html.header []
            [ Html.h1 [] [ Element.text "Chat" ]
            , Html.p [ Attr.id "me" ] [ Element.text ("You're " ++ model.name) ]
            ]
        , Html.div [ Attr.class "log" ]
            [ Keyed.ol [ Attr.id "lines", Attr.role "log" ]
                (List.map (\( n, line ) -> ( String.fromInt n, viewLine line )) model.lines)
            ]
        , Html.form [ Event.onSubmit Send ]
            [ Html.input
                [ Attr.id "draft"
                , Attr.ariaLabel "Message"
                , Attr.placeholder "Say something"
                , Attr.autocomplete "off"
                , Attr.autofocus True
                , Attr.value model.draft
                , Event.onInput Typed
                ]
            , Html.button [] [ Element.text "Send" ]
            ]
        ]


viewLine : Line -> Element msg
viewLine line =
    case line of
        Said name text ->
            Html.li [] [ Html.strong [] [ Element.text name ], Element.text (" " ++ text) ]

        Joined name ->
            Html.li [ Attr.class "note" ] [ Element.text (name ++ " joined") ]

        Left name ->
            Html.li [ Attr.class "note" ] [ Element.text (name ++ " left") ]
