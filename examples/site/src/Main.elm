port module Main exposing (Model, Msg, init, main, view)

{-| A small blog, as an app with URL routing. `start` runs it in the browser
like any Jorn app. `Site.elm` also builds it as a static site, with a page
for each route that holds this app's view at that address.
-}

import Jorn
import Jorn.Attribute as Attr
import Jorn.Effect as Effect exposing (Effect)
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Event as Event
import Jorn.Navigation as Navigation
import Json.Encode exposing (Value)
import Posts exposing (Post)
import Route exposing (Route)
import Url exposing (Url)


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


main : Jorn.Program () Model Msg
main =
    Navigation.application
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = ClickedLink
        , onUrlChange = ChangedUrl
        , ports = { toJorn = toJorn, fromJorn = fromJorn }
        }



-- MODEL


type alias Model =
    { key : Navigation.Key
    , route : Maybe Route
    , filter : String
    }


init : () -> Url -> Navigation.Key -> ( Model, Effect Msg )
init _ url key =
    ( { key = key, route = Route.fromUrl url, filter = "" }, Effect.none )



-- UPDATE


type Msg
    = ClickedLink Navigation.UrlRequest
    | ChangedUrl Url
    | Filtered String


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ClickedLink (Navigation.Internal url) ->
            ( model
            , Effect.batch [ Navigation.pushUrl model.key (Url.toString url), Effect.scrollIntoView "top" ]
            )

        ClickedLink (Navigation.External href) ->
            ( model, Navigation.load href )

        ChangedUrl url ->
            ( { model | route = Route.fromUrl url }, Effect.none )

        Filtered filter ->
            ( { model | filter = filter }, Effect.none )



-- VIEW


view : Model -> Navigation.Document Msg
view model =
    case model.route of
        Just Route.Home ->
            layout model.route "Notes" (home model.filter)

        Just Route.About ->
            layout model.route "About · Notes" about

        Just (Route.Post slug) ->
            case Posts.find slug of
                Just post ->
                    layout model.route (post.title ++ " · Notes") (viewPost post)

                Nothing ->
                    notFound

        Nothing ->
            notFound


layout : Maybe Route -> String -> List (Element Msg) -> Navigation.Document Msg
layout current title content =
    { title = title
    , body =
        [ Html.header [ Attr.id "top" ]
            [ Html.a [ Attr.class "name", Attr.href "/" ] [ Element.text "Notes" ]
            , Html.nav []
                [ navLink current Route.Home "Posts"
                , navLink current Route.About "About"
                ]
            ]
        , Html.main_ [] content
        , Html.footer [] [ Element.text "Built with Jorn.Static" ]
        ]
    }


navLink : Maybe Route -> Route -> String -> Element msg
navLink current route label =
    Html.a
        [ Attr.href (Route.toPath route)
        , if current == Just route then
            Attr.ariaCurrent "page"

          else
            Attr.none
        ]
        [ Element.text label ]


home : String -> List (Element Msg)
home filter =
    let
        shown =
            List.filter (matches filter) Posts.all
    in
    [ Html.h1 [] [ Element.text "Posts" ]
    , Html.input
        [ Attr.type_ "search"
        , Attr.ariaLabel "Filter posts"
        , Attr.placeholder "Filter posts"
        , Attr.value filter
        , Event.onInput Filtered
        ]
    , if List.isEmpty shown then
        Html.p [ Attr.class "empty" ] [ Element.text "No posts match." ]

      else
        Html.ul [ Attr.class "posts" ] (List.map summary shown)
    ]


matches : String -> Post -> Bool
matches filter post =
    String.contains (String.toLower (String.trim filter)) (String.toLower (post.title ++ " " ++ post.summary))


summary : Post -> Element msg
summary post =
    Html.li []
        [ Html.a [ Attr.href (Route.toPath (Route.Post post.slug)) ] [ Element.text post.title ]
        , Html.time [ Attr.datetime post.date ] [ Element.text post.date ]
        , Html.p [] [ Element.text post.summary ]
        ]


viewPost : Post -> List (Element msg)
viewPost post =
    [ Html.article []
        (Html.h1 [] [ Element.text post.title ]
            :: Html.time [ Attr.datetime post.date ] [ Element.text post.date ]
            :: List.map (\paragraph -> Html.p [] [ Element.text paragraph ]) post.body
        )
    , Html.p [] [ Html.a [ Attr.href "/" ] [ Element.text "All posts" ] ]
    ]


about : List (Element msg)
about =
    [ Html.h1 [] [ Element.text "About" ]
    , Html.p []
        [ Element.text "This is the example site in Jorn's repository: an app with URL routing, built into a folder of HTML pages by "
        , Html.code [] [ Element.text "jorn build" ]
        , Element.text ". Each page holds the app's own view at its address, and the app takes over in the browser."
        ]
    ]


notFound : Navigation.Document Msg
notFound =
    layout Nothing
        "Not found · Notes"
        [ Html.h1 [] [ Element.text "Not found" ]
        , Html.p [] [ Element.text "There's no page here. ", Html.a [ Attr.href "/" ] [ Element.text "See all posts" ] ]
        ]
