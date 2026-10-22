port module Site exposing (main)

{-| The app as a static site, which `jorn build` writes to `build/`: a page
for each of the app's routes, one for addresses that aren't, the stylesheet,
the compiled app, and a sitemap made from the same routes.
-}

import Jorn.Attribute as Attr
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Static as Static
import Json.Encode as Encode exposing (Value)
import Main
import Posts
import Route exposing (Route)
import Url exposing (Url)


port toJorn : Value -> Cmd msg


url : String
url =
    "https://example.com"


main : Static.Program
main =
    Static.site toJorn
        { url = url
        , pages = List.map (Just >> appPage) Route.all ++ [ appPage Nothing ]
        , assets =
            [ Static.copy "public" "/"
            , Static.compile "src/Main.elm" "/main.js"
            , Static.file "/sitemap.xml" sitemap
            ]
        }


{-| The app at one of its routes, or at none, as `404.html`. Static hosts
like GitHub Pages serve that for any address without a page, and the app
shows Not found there.
-}
appPage : Maybe Route -> Static.Page
appPage route =
    Static.page (Maybe.withDefault "/404.html" (Maybe.map Route.toPath route))
        (\pageUrl -> shell pageUrl route (Static.view { init = Main.init, view = Main.view } () pageUrl))


shell : Url -> Maybe Route -> { title : String, body : Element msg } -> Element msg
shell pageUrl route app =
    Html.html [ Attr.lang "en" ]
        [ Html.head []
            ([ Html.meta [ Attr.charset "utf-8" ]
             , Html.meta [ Attr.name "viewport", Attr.content "width=device-width, initial-scale=1" ]
             , Html.title [] [ Element.text app.title ]
             , Html.link [ Attr.rel "stylesheet", Attr.href "/style.css" ]
             ]
                ++ (case route of
                        Just found ->
                            searchable pageUrl app.title found

                        Nothing ->
                            [ Html.meta [ Attr.name "robots", Attr.content "noindex" ] ]
                   )
            )
        , Html.body []
            [ Html.div [ Attr.id "app" ] [ app.body ]
            , Html.script [ Attr.src "/main.js" ] []
            , Html.script [ Attr.type_ "module" ]
                [ Element.text "import { start } from \"/jorn.js\";\nstart(Elm.Main, document.getElementById(\"app\"));" ]
            ]
        ]


{-| What search engines and link previews read: a description, the page's one
address, the Open Graph tags previews are made from, and for a post, what it
is in JSON-LD.
-}
searchable : Url -> String -> Route -> List (Element msg)
searchable pageUrl title route =
    let
        address =
            Url.toString pageUrl

        post =
            case route of
                Route.Post slug ->
                    Posts.find slug

                _ ->
                    Nothing

        description =
            case ( route, post ) of
                ( _, Just found ) ->
                    found.summary

                ( Route.About, _ ) ->
                    "About this site, the example of a static site in Jorn's repository."

                _ ->
                    "Notes on one app that runs in the browser and builds as a static site, with Jorn."

        kind =
            if post == Nothing then
                "website"

            else
                "article"
    in
    [ Html.meta [ Attr.name "description", Attr.content description ]
    , Html.link [ Attr.rel "canonical", Attr.href address ]
    , Html.meta [ Attr.attribute "property" "og:type", Attr.content kind ]
    , Html.meta [ Attr.attribute "property" "og:title", Attr.content title ]
    , Html.meta [ Attr.attribute "property" "og:description", Attr.content description ]
    , Html.meta [ Attr.attribute "property" "og:url", Attr.content address ]
    ]
        ++ (case post of
                Just found ->
                    [ Html.script [ Attr.type_ "application/ld+json" ]
                        [ Element.text
                            (Encode.encode 0
                                (Encode.object
                                    [ ( "@context", Encode.string "https://schema.org" )
                                    , ( "@type", Encode.string "BlogPosting" )
                                    , ( "headline", Encode.string found.title )
                                    , ( "description", Encode.string found.summary )
                                    , ( "datePublished", Encode.string found.date )
                                    , ( "url", Encode.string address )
                                    ]
                                )
                            )
                        ]
                    ]

                Nothing ->
                    []
           )


sitemap : String
sitemap =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
        ++ String.concat (List.map (\route -> "  <url><loc>" ++ url ++ Route.toPath route ++ "</loc></url>\n") Route.all)
        ++ "</urlset>\n"
