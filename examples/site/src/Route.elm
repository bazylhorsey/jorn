module Route exposing (Route(..), all, fromUrl, toPath)

{-| The app's addresses, and every page the site has.

Paths end in `/`, since a static host serves `about/index.html` at `/about/`.
The app's links then go where the host serves each page, without a redirect.

-}

import Posts
import Url exposing (Url)
import Url.Parser as Parser exposing ((</>), Parser)


type Route
    = Home
    | About
    | Post String


fromUrl : Url -> Maybe Route
fromUrl url =
    Parser.parse parser url


parser : Parser (Route -> a) a
parser =
    Parser.oneOf
        [ Parser.map Home Parser.top
        , Parser.map About (Parser.s "about")
        , Parser.map Post (Parser.s "posts" </> Parser.string)
        ]


toPath : Route -> String
toPath route =
    case route of
        Home ->
            "/"

        About ->
            "/about/"

        Post slug ->
            "/posts/" ++ slug ++ "/"


{-| Every page there is, which the site builds.
-}
all : List Route
all =
    Home :: About :: List.map (\post -> Post post.slug) Posts.all
