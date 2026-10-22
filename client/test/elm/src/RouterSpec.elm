port module RouterSpec exposing (main)

{-| An app with URL routing for client/test/routing.mjs, with every kind of
link and every navigation effect, so the test can drive the page's side of
routing in jsdom, in the page and on a server.
-}

import Jorn
import Jorn.Attribute as Attr
import Jorn.Effect as Effect exposing (Effect)
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Event as Event
import Jorn.Navigation as Navigation
import Json.Encode exposing (Value)
import Url exposing (Url)


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


type alias Model =
    { key : Navigation.Key
    , url : Url
    , changes : Int
    , log : List String
    }


type Msg
    = ClickedLink Navigation.UrlRequest
    | ChangedUrl Url
    | Clicked String
    | Push String
    | Replace String
    | Back Int
    | Forward Int
    | Load String


main : Jorn.Program () Model Msg
main =
    Navigation.application
        { init = \_ url key -> ( { key = key, url = url, changes = 0, log = [] }, Effect.none )
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = ClickedLink
        , onUrlChange = ChangedUrl
        , ports = { toJorn = toJorn, fromJorn = fromJorn }
        }


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ClickedLink (Navigation.Internal url) ->
            ( { model | log = model.log ++ [ "internal " ++ Url.toString url ] }
            , Navigation.pushUrl model.key (Url.toString url)
            )

        ClickedLink (Navigation.External href) ->
            ( { model | log = model.log ++ [ "external " ++ href ] }, Effect.none )

        ChangedUrl url ->
            ( { model | url = url, changes = model.changes + 1 }, Effect.none )

        Clicked what ->
            ( { model | log = model.log ++ [ "clicked " ++ what ] }, Effect.none )

        Push url ->
            ( model, Navigation.pushUrl model.key url )

        Replace url ->
            ( model, Navigation.replaceUrl model.key url )

        Back n ->
            ( model, Navigation.back model.key n )

        Forward n ->
            ( model, Navigation.forward model.key n )

        Load url ->
            ( model, Navigation.load url )


view : Model -> Navigation.Document Msg
view model =
    { title = "Page " ++ model.url.path
    , body =
        [ Html.p [ Attr.id "path" ] [ Element.text (model.url.path ++ Maybe.withDefault "" (Maybe.map ((++) "?") model.url.query)) ]
        , Html.p [ Attr.id "changes" ] [ Element.text (String.fromInt model.changes) ]
        , Html.p [ Attr.id "log" ] [ Element.text (String.join "|" model.log) ]
        , Html.nav []
            [ Html.a [ Attr.id "about", Attr.href "/about" ] [ Html.span [ Attr.id "about-text" ] [ Element.text "About" ] ]
            , Html.a [ Attr.id "relative", Attr.href "items/7?sort=new" ] [ Element.text "Item 7" ]
            , Html.a [ Attr.id "external", Attr.href "https://elsewhere.example/page" ] [ Element.text "Elsewhere" ]
            , Html.a [ Attr.id "blank", Attr.href "/blank", Attr.attribute "target" "_blank" ] [ Element.text "New tab" ]
            , Html.a [ Attr.id "download", Attr.href "/file.txt", Attr.attribute "download" "" ] [ Element.text "Download" ]
            , Html.a [ Attr.id "handled", Attr.href "/handled", Event.preventDefault (Event.onClick (Clicked "handled")) ] [ Element.text "Handled" ]
            , Element.element "jorn-server-component" [] [ Html.a [ Attr.id "nested", Attr.href "/nested" ] [ Element.text "Nested" ] ]
            ]
        , Html.button [ Attr.id "push", Event.onClick (Push "?page=2") ] []
        , Html.button [ Attr.id "replace", Event.onClick (Replace "/replaced") ] []
        , Html.button [ Attr.id "back", Event.onClick (Back 1) ] []
        , Html.button [ Attr.id "forward", Event.onClick (Forward 1) ] []
        , Html.button [ Attr.id "load", Event.onClick (Load "https://elsewhere.example/loaded") ] []
        ]
    }
