module Jorn.Static exposing
    ( Program, site
    , Page, page
    , Asset, copy, compile, file
    , view
    )

{-| Build an app as a static site: a folder of HTML pages, scripts and
other files that any static host serves as they are, like GitHub Pages.

A site is a small Elm program of its own, which `jorn build` runs in Node.
It lists the pages, each a whole HTML document, and the files that go next
to them:

    port module Site exposing (main)

    import Jorn.Static as Static
    import Json.Encode exposing (Value)
    import Main
    import Route

    port toJorn : Value -> Cmd msg

    main : Static.Program
    main =
        Static.site toJorn
            { url = "https://example.com"
            , pages = List.map (Route.toPath >> appPage) Route.all ++ [ appPage "/404.html" ]
            , assets =
                [ Static.copy "public" "/"
                , Static.compile "src/Main.elm" "/main.js"
                ]
            }

    appPage : String -> Static.Page
    appPage path =
        Static.page path
            (\url -> shell (Static.view { init = Main.init, view = Main.view } () url))

Here every page is the app, from `Jorn.Navigation`, at one of its routes, so
the same app runs as a client app or builds as a static site. A page can
also be any view of your own.

`jorn build` writes each page to its path, as `about/index.html` for
`"/about"`, copies and compiles the assets, and copies `client/jorn.js` to
`/jorn.js`. Scripts and stylesheets that pages refer to from the site's root,
like `"/main.js"`, get a hash of their contents added to their URL, so a
returning visitor never gets new HTML with an old script.

A page's HTML is what someone sees before the app's script has loaded, and
what search engines and link previews read. Each page's function gets the
page's URL, so its `<head>` can have its own description, canonical link and
Open Graph tags, and `file` can make a sitemap from the same list as the
pages. In the browser, `start` mounts the app over the page's HTML, from the
same view, so nothing changes on screen.


# Sites

@docs Program, site


# Pages

@docs Page, page


# Other files

@docs Asset, copy, compile, file


# Apps

@docs view

-}

import Jorn.Effect exposing (Effect)
import Jorn.Element exposing (Element)
import Jorn.Internal.Navigation as Internal
import Jorn.Internal.Vdom as Vdom
import Jorn.Navigation as Navigation
import Json.Encode as Encode exposing (Value)
import Url exposing (Url)


{-| A site, ready to be the `main` that `jorn build` runs.
-}
type alias Program =
    Platform.Program () () Never


{-| Describe a site. `url` is where its root will be served, like
`"https://example.com"`, so each page knows its own URL. For a site in a
folder of a domain, like a GitHub project page, give the folder too, as in
`"https://you.github.io/project"`, and put it in front of the paths your
pages refer to: `"/project/main.js"`.

The site goes to `jorn build` through a port called `toJorn`, which you
declare:

    port toJorn : Value -> Cmd msg

-}
site :
    (Value -> Cmd Never)
    ->
        { url : String
        , pages : List Page
        , assets : List Asset
        }
    -> Program
site toJorn config =
    Platform.worker
        { init = \_ -> ( (), toJorn (encode config) )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


encode : { url : String, pages : List Page, assets : List Asset } -> Value
encode config =
    let
        root =
            if String.endsWith "/" config.url then
                String.dropRight 1 config.url

            else
                config.url
    in
    case Url.fromString config.url of
        Just { query, fragment } ->
            if query /= Nothing || fragment /= Nothing then
                problem ("The site's url, " ++ config.url ++ ", should be where its root is, without a query or a fragment.")

            else
                encodePages root config

        Nothing ->
            problem ("The site's url, " ++ config.url ++ ", isn't a URL. It should look like \"https://example.com\".")


encodePages : String -> { url : String, pages : List Page, assets : List Asset } -> Value
encodePages root config =
    let
        rendered =
            List.map
                (\(Page path render) ->
                    case ( String.startsWith "/" path, Url.fromString (root ++ path) ) of
                        ( True, Just url ) ->
                            Ok (Encode.object [ ( "path", Encode.string path ), ( "html", Encode.string (render url) ) ])

                        _ ->
                            Err ("The page " ++ path ++ " needs a path from the site's root, like \"/about\".")
                )
                config.pages
    in
    case List.filterMap failure rendered of
        first :: _ ->
            problem first

        [] ->
            Encode.object
                [ ( "site"
                  , Encode.object
                        [ ( "url", Encode.string root )
                        , ( "pages", Encode.list identity (List.filterMap Result.toMaybe rendered) )
                        , ( "assets", Encode.list encodeAsset config.assets )
                        ]
                  )
                ]


problem : String -> Value
problem text =
    Encode.object [ ( "error", Encode.string text ) ]


failure : Result String a -> Maybe String
failure result =
    case result of
        Err text ->
            Just text

        Ok _ ->
            Nothing


{-| One HTML page of the site.
-}
type Page
    = Page String (Url -> String)


{-| A page at this path from the site's root, with the whole document that
goes there, from `<html>` down. The function gets the page's URL.

A path like `"/about"` is written to `about/index.html`, which static hosts
serve at `/about/`, and `"/"` to `index.html`. A path that ends in `.html`,
like `"/404.html"`, is written to that file.

Pages from a list of values are a `List.map` away:

    List.map (\post -> Static.page ("/posts/" ++ post.slug) (postPage post)) posts

-}
page : String -> (Url -> Element msg) -> Page
page path document =
    Page path (\url -> Jorn.Element.toDocumentString (document url))


{-| A file the site serves that isn't a page.
-}
type Asset
    = Copy String String
    | Compile String String
    | File String String


{-| Copy a file, or everything in a folder, from the folder `jorn build`
runs in to this path in the site:

    Static.copy "public" "/"

    Static.copy "images/logo.svg" "/logo.svg"

-}
copy : String -> String -> Asset
copy =
    Copy


{-| Compile an Elm program with `elm make --optimize` to this path in the
site. This is how the app gets to the browser:

    Static.compile "src/Main.elm" "/main.js"

-}
compile : String -> String -> Asset
compile =
    Compile


{-| A file with this text, like a sitemap or a feed made from the same list
as the pages:

    Static.file "/robots.txt" "User-agent: *\nAllow: /\n"

-}
file : String -> String -> Asset
file =
    File


encodeAsset : Asset -> Value
encodeAsset asset =
    case asset of
        Copy from to ->
            Encode.object [ ( "copy", Encode.string from ), ( "to", Encode.string to ) ]

        Compile from to ->
            Encode.object [ ( "compile", Encode.string from ), ( "to", Encode.string to ) ]

        File to text ->
            Encode.object [ ( "text", Encode.string text ), ( "to", Encode.string to ) ]


{-| What an app made with `Jorn.Navigation.application` shows at this URL:
its `view` of the model its `init` gives, with these flags. Put `body` in
the element the page starts the app in, as its only child, and `title` in
the page's `<title>`:

    shell : { title : String, body : Element msg } -> Element msg
    shell app =
        Html.html [ Attr.lang "en" ]
            [ Html.head []
                [ Html.meta [ Attr.charset "utf-8" ]
                , Html.title [] [ Element.text app.title ]
                , Html.link [ Attr.rel "stylesheet", Attr.href "/style.css" ]
                ]
            , Html.body []
                [ Html.div [ Attr.id "app" ] [ app.body ]
                , Html.script [ Attr.src "/main.js" ] []
                , Html.script [ Attr.type_ "module" ]
                    [ Element.text "import { start } from \"/jorn.js\";\nstart(Elm.Main, document.getElementById(\"app\"));" ]
                ]
            ]

`body` is the view as `start` mounts it, so the page and the app agree on
every node. Commands from `init` don't run: anything a page needs at build
time comes from the flags or from Elm code the site shares with the app.

Give it your app's `init` and `view`, not the record you give
`Navigation.application`, since the site has a port called `toJorn` of its
own and a program can't have two ports with the same name.

-}
view :
    { a
        | init : flags -> Url -> Navigation.Key -> ( model, Effect msg )
        , view : model -> Navigation.Document msg
    }
    -> flags
    -> Url
    -> { title : String, body : Element msg }
view app flags url =
    let
        ( model, _ ) =
            app.init flags url Internal.Key

        document =
            app.view model
    in
    { title = document.title
    , body = Vdom.root (Jorn.Element.fragment document.body)
    }
