module Jorn.Internal.Vdom exposing
    ( Attribute(..)
    , EventOptions
    , Facts
    , Html(..)
    , Node(..)
    , defaultOptions
    , encodeNode
    , encodeOptions
    , facts
    , map
    , mapAttribute
    , toNode
    )

{-| Internal representation. Not exposed from the package, so constructors
stay private while tests and sibling modules can still see them.

`Html` carries decoders (it is what your program builds and what event routing
walks). `Node` is the msg-free projection of it: pure data, safe to serialize,
and what every patch and mount payload is made of.

-}

import Dict exposing (Dict)
import Json.Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


type Html msg
    = Element String String (List (Attribute msg)) (List (Html msg))
      -- namespace, tag, attributes, children
    | Text String


type Attribute msg
    = Attr String String
    | Prop String Value
    | On String EventOptions (Decoder msg)


{-| Event options are static on purpose. A server component has to tell the
client up front whether to call preventDefault, because the decision can't
wait for a round trip. `include` lists the dotted event fields the client
must serialize and send back (for example `target.value`).
-}
type alias EventOptions =
    { preventDefault : Bool
    , stopPropagation : Bool
    , include : List String
    }


defaultOptions : EventOptions
defaultOptions =
    { preventDefault = False, stopPropagation = False, include = [] }



-- NORMALIZATION


{-| An element's attribute list folded into lookup tables. Later entries win,
except `class`, which accumulates like it does in elm/html.
-}
type alias Facts msg =
    { attrs : Dict String String
    , props : Dict String Value
    , events : Dict String ( EventOptions, Decoder msg )
    }


facts : List (Attribute msg) -> Facts msg
facts attributes =
    List.foldl addFact { attrs = Dict.empty, props = Dict.empty, events = Dict.empty } attributes


addFact : Attribute msg -> Facts msg -> Facts msg
addFact attribute acc =
    case attribute of
        Attr "class" value ->
            { acc | attrs = Dict.update "class" (mergeClass value) acc.attrs }

        Attr name value ->
            { acc | attrs = Dict.insert name value acc.attrs }

        Prop name value ->
            { acc | props = Dict.insert name value acc.props }

        On name options decoder ->
            { acc | events = Dict.insert name ( options, decoder ) acc.events }


mergeClass : String -> Maybe String -> Maybe String
mergeClass value existing =
    case existing of
        Nothing ->
            Just value

        Just previous ->
            if String.isEmpty value then
                Just previous

            else if String.isEmpty previous then
                Just value

            else
                Just (previous ++ " " ++ value)



-- PROJECTION


type Node
    = NodeElement
        { namespace : String
        , tag : String
        , attrs : Dict String String
        , props : Dict String Value
        , events : Dict String EventOptions
        , children : List Node
        }
    | NodeText String


toNode : Html msg -> Node
toNode html =
    case html of
        Text content ->
            NodeText content

        Element namespace tag attributes children ->
            let
                f =
                    facts attributes
            in
            NodeElement
                { namespace = namespace
                , tag = tag
                , attrs = f.attrs
                , props = f.props
                , events = Dict.map (\_ ( options, _ ) -> options) f.events
                , children = List.map toNode children
                }


encodeNode : Node -> Value
encodeNode node =
    case node of
        NodeText content ->
            Encode.object [ ( "text", Encode.string content ) ]

        NodeElement r ->
            Encode.object
                [ ( "tag", Encode.string r.tag )
                , ( "namespace", Encode.string r.namespace )
                , ( "attrs", Encode.dict identity Encode.string r.attrs )
                , ( "props", Encode.dict identity identity r.props )
                , ( "events", Encode.dict identity encodeOptions r.events )
                , ( "children", Encode.list encodeNode r.children )
                ]


encodeOptions : EventOptions -> Value
encodeOptions options =
    Encode.object
        [ ( "preventDefault", Encode.bool options.preventDefault )
        , ( "stopPropagation", Encode.bool options.stopPropagation )
        , ( "include", Encode.list Encode.string options.include )
        ]



-- MAPPING


{-| Eager: walks the subtree and wraps every decoder. elm/html makes `map`
lazy with kernel code, which a pure package can't do. Lazy map is on the roadmap.
-}
map : (a -> b) -> Html a -> Html b
map f html =
    case html of
        Text content ->
            Text content

        Element namespace tag attributes children ->
            Element namespace tag (List.map (mapAttribute f) attributes) (List.map (map f) children)


mapAttribute : (a -> b) -> Attribute a -> Attribute b
mapAttribute f attribute =
    case attribute of
        Attr name value ->
            Attr name value

        Prop name value ->
            Prop name value

        On name options decoder ->
            On name options (Json.Decode.map f decoder)
