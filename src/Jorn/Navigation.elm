module Jorn.Navigation exposing
    ( application, Document, UrlRequest(..)
    , Key, pushUrl, replaceUrl, back, forward
    , load, reload, reloadAndSkipCache
    )

{-| URL routing, for an app that owns the page's address. It's
`Browser.application` and `Browser.Navigation` for Jorn: `init` gets the URL,
clicking a link gives you a message instead of loading a page, and you change
the address with effects. Parse URLs with `elm/url`, as you would in any Elm
app.

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

    update : Msg -> Model -> ( Model, Effect Msg )
    update msg model =
        case msg of
            ClickedLink (Navigation.Internal url) ->
                ( model, Navigation.pushUrl model.key (Url.toString url) )

            ClickedLink (Navigation.External href) ->
                ( model, Navigation.load href )

            ChangedUrl url ->
                ( { model | route = Route.fromUrl url }, Effect.none )

The page starts it with `start`, or `stream` when it runs on a server, as
for any Jorn app. Nothing else changes in server mode: the page tells the
server where it is and which links were clicked, and the server's navigation
effects travel back to the page.


# Programs

@docs application, Document, UrlRequest


# Changing the address

@docs Key, pushUrl, replaceUrl, back, forward


# Leaving

@docs load, reload, reloadAndSkipCache

-}

import Jorn
import Jorn.Effect exposing (Effect)
import Jorn.Element exposing (Element)
import Jorn.Internal.Effect as Effect exposing (Item(..))
import Jorn.Internal.Navigation as Internal
import Jorn.Internal.Runtime as Runtime
import Json.Encode as Encode
import Url exposing (Url)


{-| An app that owns the page's address, like `Browser.application`:

  - `init` gets the URL the page is at, and a `Key` for changing it.
  - Clicking a link in the app gives you `onUrlRequest` instead of loading a
    page, unless the link has a `target` or `download` attribute, the user
    held a modifier key, or a handler already prevented the click's default.
  - `onUrlChange` tells you the address changed: after `pushUrl` or
    `replaceUrl`, or when someone uses the browser's back and forward
    buttons.
  - `view` gives the page's title as well as what goes in the app's
    element.

The app still lives in the element you start it in, and only follows links
in that element. Links in a server component inside the app belong to that
component.

The page only knows `http` and `https` addresses as URLs, so this kind of
app can't start from a file opened in the browser. Serve it instead.

-}
application :
    { init : flags -> Url -> Key -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : model -> Document msg
    , subscriptions : model -> Sub msg
    , onUrlRequest : UrlRequest -> msg
    , onUrlChange : Url -> msg
    , ports : Jorn.Ports msg
    }
    -> Jorn.Program flags model msg
application config =
    Runtime.program
        { init =
            \flags ->
                Runtime.AtUrl
                    (\address -> Maybe.map (\url -> config.init flags url Internal.Key) (Url.fromString address))
        , update = config.update
        , view =
            \model ->
                let
                    document =
                        config.view model
                in
                { title = Just document.title, body = Jorn.Element.fragment document.body }
        , subscriptions = config.subscriptions
        , ports = config.ports
        , routing =
            Just
                { onUrlChange = \address -> Maybe.map config.onUrlChange (Url.fromString address)
                , onLink = \current href -> config.onUrlRequest (request current href)
                }
        }


{-| What an app's `view` gives: the page's title, and what goes in the
app's element.
-}
type alias Document msg =
    { title : String
    , body : List (Element msg)
    }


{-| A link someone clicked. `Internal` links go somewhere on the same site
(the same protocol, host and port), and `External` ones go anywhere else,
which usually means `load`.
-}
type UrlRequest
    = Internal Url
    | External String


request : String -> String -> UrlRequest
request current href =
    case ( Url.fromString current, Url.fromString href ) of
        ( Just here, Just there ) ->
            if here.protocol == there.protocol && here.host == there.host && here.port_ == there.port_ then
                Internal there

            else
                External href

        _ ->
            External href


{-| Only `application` gives you a `Key`, so only an app that hears about
changes of address can make them.
-}
type alias Key =
    Internal.Key


{-| Add an entry to the browser's history and go to this address, without
loading a page. `onUrlChange` follows with the new URL. The address can be
relative, like `"/about"` or `"?page=2"`, and must be on the same site.
-}
pushUrl : Key -> String -> Effect msg
pushUrl _ url =
    navigate "push" (Encode.string url)


{-| Like `pushUrl`, but replace the current history entry instead of adding
one. Good for addresses that track state, like search terms, where the back
button shouldn't go through every keystroke.
-}
replaceUrl : Key -> String -> Effect msg
replaceUrl _ url =
    navigate "replace" (Encode.string url)


{-| Go back this many entries in the browser's history, as the back button
does. `onUrlChange` follows if the address changes. `back key 0` does
nothing.
-}
back : Key -> Int -> Effect msg
back _ n =
    go -n


{-| Go forward this many entries in the browser's history. `onUrlChange`
follows if the address changes.
-}
forward : Key -> Int -> Effect msg
forward _ n =
    go n


go : Int -> Effect msg
go n =
    if n == 0 then
        Jorn.Effect.none

    else
        navigate "go" (Encode.int n)


{-| Load this address, leaving the app, as following an ordinary link
does.
-}
load : String -> Effect msg
load url =
    navigate "load" (Encode.string url)


{-| Reload the page, which starts the app again.
-}
reload : Effect msg
reload =
    navigate "reload" (Encode.bool False)


{-| Reload the page without using the browser's cache.
-}
reloadAndSkipCache : Effect msg
reloadAndSkipCache =
    navigate "reload" (Encode.bool True)


navigate : String -> Encode.Value -> Effect msg
navigate kind value =
    Effect.Effect [ Navigate (Encode.object [ ( kind, value ) ]) ]
