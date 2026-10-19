port module HttpSpec exposing (main)

{-| A server component that makes every kind of request elm/http can, for
server/test/http-elm.mjs. Each result shows up in the view under its own id,
where the test reads it.
-}

import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import Dict exposing (Dict)
import Http
import Jorn
import Jorn.Attribute as Attr
import Jorn.Effect as Effect exposing (Effect)
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Event as Event
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)
import Process
import Task


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


type alias Flags =
    { base : String
    , nowhere : String
    }


type alias Model =
    { base : String
    , results : Dict String String
    }


type Msg
    = Got String String
    | Progressed String Http.Progress
    | Fetch


main : Jorn.Program Flags Model Msg
main =
    Jorn.application
        { init = init
        , update = update
        , view = view
        , subscriptions =
            \_ ->
                Sub.batch
                    [ Http.track "upload" (Progressed "upload")
                    , Http.track "download" (Progressed "download")
                    ]
        , ports = { toJorn = toJorn, fromJorn = fromJorn }
        }


init : Flags -> ( Model, Effect Msg )
init { base, nowhere } =
    ( { base = base, results = Dict.empty }
    , Effect.fromCmd <|
        Cmd.batch
            [ Http.get { url = base ++ "/text", expect = Http.expectString (got "text" identity) }
            , Http.get { url = base ++ "/json", expect = Http.expectJson (got "json" String.fromInt) (Decode.field "a" Decode.int) }
            , Http.post
                { url = base ++ "/echo"
                , body = Http.jsonBody (Encode.object [ ( "b", Encode.int 2 ) ])
                , expect =
                    Http.expectJson (got "post" identity)
                        (Decode.map2 (\method text -> method ++ " " ++ text)
                            (Decode.field "method" Decode.string)
                            (Decode.field "text" Decode.string)
                        )
                }
            , Http.request
                { method = "GET"
                , headers = [ Http.header "X-Custom" "yes" ]
                , url = base ++ "/echo"
                , body = Http.emptyBody
                , expect = Http.expectStringResponse (got "headers" identity) (resolve metadata)
                , timeout = Nothing
                , tracker = Nothing
                }
            , Http.get { url = base ++ "/missing", expect = Http.expectString (got "missing" identity) }
            , Http.request
                { method = "GET"
                , headers = []
                , url = base ++ "/slow"
                , body = Http.emptyBody
                , expect = Http.expectString (got "timeout" identity)
                , timeout = Just 50
                , tracker = Nothing
                }
            , Http.get { url = "/relative", expect = Http.expectString (got "badurl" identity) }
            , Http.get { url = nowhere, expect = Http.expectString (got "network" identity) }
            , Http.get { url = base ++ "/bytes", expect = Http.expectBytesResponse (got "bytes" identity) (resolve width) }
            , Http.request
                { method = "PUT"
                , headers = []
                , url = base ++ "/echo"
                , body = Http.bytesBody "application/octet-stream" three
                , expect = Http.expectJson (got "upload" String.fromInt) (Decode.field "length" Decode.int)
                , timeout = Nothing
                , tracker = Just "upload"
                }
            , Http.request
                { method = "GET"
                , headers = []
                , url = base ++ "/big"
                , body = Http.emptyBody
                , expect = Http.expectBytesResponse (got "download" identity) (resolve width)
                , timeout = Nothing
                , tracker = Just "download"
                }
            , Http.request
                { method = "GET"
                , headers = []
                , url = base ++ "/slow"
                , body = Http.emptyBody
                , expect = Http.expectString (got "cancelled" identity)
                , timeout = Nothing
                , tracker = Just "cancel"
                }
            , Http.post
                { url = base ++ "/echo"
                , body = Http.multipartBody [ Http.stringPart "name" "jorn", Http.bytesPart "file" "text/plain" three ]
                , expect = Http.expectJson (got "multipart" identity) multipart
                }
            , Process.sleep 10
                |> Task.andThen
                    (\_ ->
                        Http.task
                            { method = "GET"
                            , headers = []
                            , url = base ++ "/text"
                            , body = Http.emptyBody
                            , resolver = Http.stringResolver (resolve (\_ body -> Ok body))
                            , timeout = Nothing
                            }
                    )
                |> Task.attempt (got "task" identity)
            ]
    )


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        Got name result ->
            ( { model | results = Dict.insert name result model.results }
            , if name == "text" then
                -- The tracked request to /slow is still waiting.
                Effect.fromCmd (Http.cancel "cancel")

              else
                Effect.none
            )

        Progressed name (Http.Sending { sent, size }) ->
            ( { model | results = Dict.insert (name ++ "-sent") ("sent " ++ String.fromInt sent ++ " of " ++ String.fromInt size) model.results }
            , Effect.none
            )

        Progressed name (Http.Receiving { received, size }) ->
            ( { model | results = Dict.insert (name ++ "-received") ("received " ++ String.fromInt received ++ " of " ++ Maybe.withDefault "?" (Maybe.map String.fromInt size)) model.results }
            , Effect.none
            )

        Fetch ->
            ( model, Effect.fromCmd (Http.get { url = model.base ++ "/text", expect = Http.expectString (got "event" identity) }) )


view : Model -> Element Msg
view model =
    Html.div []
        [ Html.button [ Attr.id "fetch", Event.onClick Fetch ] [ Element.text "Fetch" ]
        , Html.ul [] (List.map (\( name, result ) -> Html.li [ Attr.id name ] [ Element.text result ]) (Dict.toList model.results))
        ]


got : String -> (a -> String) -> Result Http.Error a -> Msg
got name toString result =
    Got name <|
        case result of
            Ok value ->
                toString value

            Err (Http.BadUrl url) ->
                "BadUrl " ++ url

            Err Http.Timeout ->
                "Timeout"

            Err Http.NetworkError ->
                "NetworkError"

            Err (Http.BadStatus status) ->
                "BadStatus " ++ String.fromInt status

            Err (Http.BadBody problem) ->
                "BadBody " ++ problem


resolve : (Http.Metadata -> body -> Result Http.Error a) -> Http.Response body -> Result Http.Error a
resolve good response =
    case response of
        Http.BadUrl_ url ->
            Err (Http.BadUrl url)

        Http.Timeout_ ->
            Err Http.Timeout

        Http.NetworkError_ ->
            Err Http.NetworkError

        Http.BadStatus_ { statusCode } _ ->
            Err (Http.BadStatus statusCode)

        Http.GoodStatus_ meta body ->
            good meta body


metadata : Http.Metadata -> String -> Result Http.Error String
metadata meta body =
    Ok
        (String.join " "
            [ String.fromInt meta.statusCode
            , meta.statusText
            , Maybe.withDefault "no content type" (Dict.get "content-type" meta.headers)
            , Result.withDefault "no echo" (Decode.decodeString (Decode.field "custom" Decode.string) body)
            , if meta.url == "" then
                "no url"

              else
                "from " ++ meta.url
            ]
        )


width : Http.Metadata -> Bytes -> Result Http.Error String
width _ bytes =
    let
        size =
            Bytes.width bytes

        ends =
            Bytes.Decode.map2 (\first last -> String.fromInt first ++ ".." ++ String.fromInt last)
                Bytes.Decode.unsignedInt8
                (Bytes.Decode.bytes (size - 2) |> Bytes.Decode.andThen (\_ -> Bytes.Decode.unsignedInt8))
    in
    Ok (String.fromInt size ++ " bytes, " ++ Maybe.withDefault "unreadable" (Bytes.Decode.decode ends bytes))


multipart : Decode.Decoder String
multipart =
    Decode.map2
        (\contentType text ->
            if String.startsWith "multipart/form-data; boundary=" contentType && String.contains "jorn" text then
                "multipart, with its parts"

            else
                contentType ++ " " ++ text
        )
        (Decode.field "contentType" Decode.string)
        (Decode.field "text" Decode.string)


three : Bytes
three =
    Bytes.Encode.encode (Bytes.Encode.sequence (List.map Bytes.Encode.unsignedInt8 [ 1, 2, 250 ]))
