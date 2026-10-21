port module Main exposing (main)

{-| A todo list. An ordinary Elm program: `view` returns Jorn elements,
`update` returns effects, and the page starts it with `start` from
client/jorn.js, which also keeps the list in localStorage.
-}

import Jorn
import Jorn.Attribute as Attr
import Jorn.Effect as Effect exposing (Effect)
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Element.Keyed as Keyed
import Jorn.Element.Svg as Svg
import Jorn.Event as Event
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


main : Jorn.Program Value Model Msg
main =
    Jorn.application
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , ports = { toJorn = toJorn, fromJorn = fromJorn }
        }



-- MODEL


type alias Model =
    { todos : List Todo
    , draft : String
    , editing : Maybe Editing
    , filter : Filter
    , nextId : Int
    }


type alias Todo =
    { id : Int
    , title : String
    , done : Bool
    }


type alias Editing =
    { id : Int
    , title : String
    }


type Filter
    = All
    | Active
    | Completed


{-| The flags are the list the page saved last time.
-}
init : Value -> ( Model, Effect Msg )
init saved =
    let
        todos =
            Decode.decodeValue (Decode.list todoDecoder) saved
                |> Result.withDefault []
    in
    ( { todos = todos
      , draft = ""
      , editing = Nothing
      , filter = All
      , nextId = 1 + List.foldl (\todo highest -> max todo.id highest) 0 todos
      }
    , Effect.none
    )



-- UPDATE


type Msg
    = Draft String
    | Add
    | Toggle Int Bool
    | Delete Int
    | ClearCompleted
    | Edit Todo
    | Retitle String
    | EditKey String
    | Finish
    | Show Filter


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        Draft draft ->
            ( { model | draft = draft }, Effect.none )

        Add ->
            case String.trim model.draft of
                "" ->
                    ( model, Effect.none )

                title ->
                    save
                        { model
                            | todos = model.todos ++ [ { id = model.nextId, title = title, done = False } ]
                            , draft = ""
                            , nextId = model.nextId + 1
                        }

        Toggle id done ->
            save { model | todos = List.map (\todo -> ifId id (\t -> { t | done = done }) todo) model.todos }

        Delete id ->
            save { model | todos = List.filter (\todo -> todo.id /= id) model.todos }

        ClearCompleted ->
            save { model | todos = List.filter (not << .done) model.todos }

        Edit todo ->
            ( { model | editing = Just { id = todo.id, title = todo.title } }
            , Effect.focus (editorId todo.id)
            )

        Retitle title ->
            ( { model | editing = Maybe.map (\editing -> { editing | title = title }) model.editing }
            , Effect.none
            )

        EditKey "Escape" ->
            ( { model | editing = Nothing }, Effect.none )

        EditKey _ ->
            ( model, Effect.none )

        Finish ->
            case model.editing of
                Nothing ->
                    ( model, Effect.none )

                Just editing ->
                    case String.trim editing.title of
                        "" ->
                            update (Delete editing.id) { model | editing = Nothing }

                        title ->
                            save
                                { model
                                    | editing = Nothing
                                    , todos = List.map (\todo -> ifId editing.id (\t -> { t | title = title }) todo) model.todos
                                }

        Show filter ->
            ( { model | filter = filter }, Effect.none )


{-| Hand the list to the page, which keeps it in localStorage.
-}
save : Model -> ( Model, Effect Msg )
save model =
    ( model, Effect.client "save" (Encode.list encodeTodo model.todos) )


ifId : Int -> (Todo -> Todo) -> Todo -> Todo
ifId id change todo =
    if todo.id == id then
        change todo

    else
        todo



-- VIEW


view : Model -> Element Msg
view model =
    Html.main_ []
        [ Html.header []
            [ Html.h1 [] [ Element.text "Todos" ]
            , progress model.todos
            ]
        , Html.form [ Event.onSubmit Add ]
            [ Html.input
                [ Attr.ariaLabel "New todo"
                , Attr.placeholder "What needs doing?"
                , Attr.autofocus True
                , Attr.value model.draft
                , Event.onInput Draft
                ]
            ]
        , Keyed.ul []
            (List.map (\todo -> ( String.fromInt todo.id, viewTodo model.editing todo )) (visible model))
        , viewFooter model
        ]


{-| A ring that fills up as todos get done.
-}
progress : List Todo -> Element msg
progress todos =
    let
        total =
            List.length todos

        done =
            List.length (List.filter .done todos)

        circumference =
            2 * pi * 16

        filled =
            if total == 0 then
                0

            else
                circumference * toFloat done / toFloat total
    in
    Svg.svg
        [ Attr.attribute "viewBox" "0 0 40 40"
        , Attr.class "progress"
        , Attr.role "progressbar"
        , Attr.ariaLabel "Completed"
        , Attr.ariaValuemin "0"
        , Attr.ariaValuemax (String.fromInt total)
        , Attr.ariaValuenow (String.fromInt done)
        ]
        [ Svg.circle [ Attr.class "track", Attr.attribute "cx" "20", Attr.attribute "cy" "20", Attr.attribute "r" "16" ] []
        , Svg.circle
            [ Attr.class "fill"
            , Attr.attribute "cx" "20"
            , Attr.attribute "cy" "20"
            , Attr.attribute "r" "16"
            , Attr.attribute "stroke-dasharray" (String.fromFloat filled ++ " " ++ String.fromFloat circumference)
            , Attr.attribute "transform" "rotate(-90 20 20)"
            ]
            []
        ]


viewTodo : Maybe Editing -> Todo -> Element Msg
viewTodo editing todo =
    case editing of
        Just edit ->
            if edit.id == todo.id then
                viewEditor edit

            else
                viewItem todo

        Nothing ->
            viewItem todo


{-| Built again only when the todo changes, so a render builds just the items
that did. The todo is everything the item shows, and the encoder that saves
it already says what it is.
-}
viewItem : Todo -> Element Msg
viewItem todo =
    Element.memo [ encodeTodo todo ]
        (\() ->
            Html.li [ Attr.classes [ ( "done", todo.done ) ] ]
                [ Html.label []
                    [ Html.input
                        [ Attr.type_ "checkbox"
                        , Attr.checked todo.done
                        , Event.onCheck (Toggle todo.id)
                        ]
                    , Element.text todo.title
                    ]
                , Html.button [ Attr.ariaLabel ("Edit " ++ todo.title), Event.onClick (Edit todo) ] [ Element.text "Edit" ]
                , Html.button [ Attr.ariaLabel ("Delete " ++ todo.title), Event.onClick (Delete todo.id) ] [ Element.text "×" ]
                ]
        )


viewEditor : Editing -> Element Msg
viewEditor editing =
    Html.li []
        [ Html.form [ Event.onSubmit Finish ]
            [ Html.input
                [ Attr.id (editorId editing.id)
                , Attr.ariaLabel "Title"
                , Attr.value editing.title
                , Event.onInput Retitle
                , Event.onKeydown EditKey
                , Event.onBlur Finish
                ]
            ]
        ]


viewFooter : Model -> Element Msg
viewFooter model =
    if List.isEmpty model.todos then
        Element.none

    else
        let
            left =
                List.length (List.filter (not << .done) model.todos)
        in
        Html.footer []
            [ Html.p [ Attr.ariaLive "polite" ]
                [ Element.text (String.fromInt left ++ " left") ]
            , Html.div [ Attr.role "group", Attr.ariaLabel "Show" ]
                (List.map (viewFilter model.filter) [ All, Active, Completed ])
            , if left < List.length model.todos then
                Html.button [ Event.onClick ClearCompleted ] [ Element.text "Clear completed" ]

              else
                Element.none
            ]


viewFilter : Filter -> Filter -> Element Msg
viewFilter current filter =
    Html.button
        [ Attr.ariaPressed
            (if filter == current then
                "true"

             else
                "false"
            )
        , Event.onClick (Show filter)
        ]
        [ Element.text (filterName filter) ]


visible : Model -> List Todo
visible model =
    case model.filter of
        All ->
            model.todos

        Active ->
            List.filter (not << .done) model.todos

        Completed ->
            List.filter .done model.todos


filterName : Filter -> String
filterName filter =
    case filter of
        All ->
            "All"

        Active ->
            "Active"

        Completed ->
            "Completed"


editorId : Int -> String
editorId id =
    "edit-" ++ String.fromInt id



-- SAVING


todoDecoder : Decoder Todo
todoDecoder =
    Decode.map3 Todo
        (Decode.field "id" Decode.int)
        (Decode.field "title" Decode.string)
        (Decode.field "done" Decode.bool)


encodeTodo : Todo -> Value
encodeTodo todo =
    Encode.object
        [ ( "id", Encode.int todo.id )
        , ( "title", Encode.string todo.title )
        , ( "done", Encode.bool todo.done )
        ]
