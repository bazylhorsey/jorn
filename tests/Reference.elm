module Reference exposing (apply, render)

{-| A reference implementation of the client patcher, over `Node`.

This is the executable spec the JS runtime has to match: if `apply (diff a b)`
turns `a` into `b` here, a conforming client does the same to the real DOM.

-}

import Dict
import Jorn.Internal.Patch exposing (Patch(..), Path)
import Jorn.Internal.Vdom as Vdom exposing (Node(..))
import Json.Encode as Encode


{-| Canonical string form of a node, for equality checks.
-}
render : Node -> String
render node =
    Encode.encode 0 (Vdom.encodeNode node)


{-| `Nothing` means a patch was invalid for the tree it was applied to.
-}
apply : List Patch -> Node -> Maybe Node
apply patches root =
    List.foldl (\patch acc -> Maybe.andThen (applyOne patch) acc) (Just root) patches


applyOne : Patch -> Node -> Maybe Node
applyOne patch root =
    case patch of
        Replace path node ->
            at path (\_ -> Just node) root

        SetText path content ->
            at path
                (\n ->
                    case n of
                        NodeText _ ->
                            Just (NodeText content)

                        NodeElement _ ->
                            Nothing
                )
                root

        SetAttribute path name value ->
            element path (\r -> { r | attrs = Dict.insert name value r.attrs }) root

        RemoveAttribute path name ->
            element path (\r -> { r | attrs = Dict.remove name r.attrs }) root

        SetProperty path name value ->
            element path (\r -> { r | props = Dict.insert name value r.props }) root

        RemoveProperty path name ->
            element path (\r -> { r | props = Dict.remove name r.props }) root

        SetEvent path name options ->
            element path (\r -> { r | events = Dict.insert name options r.events }) root

        RemoveEvent path name ->
            element path (\r -> { r | events = Dict.remove name r.events }) root

        Append path nodes ->
            element path (\r -> { r | children = r.children ++ nodes }) root

        Truncate path length ->
            element path (\r -> { r | children = List.take length r.children }) root


element :
    Path
    ->
        ({ namespace : String, tag : String, attrs : Dict.Dict String String, props : Dict.Dict String Encode.Value, events : Dict.Dict String Vdom.EventOptions, children : List Node }
         -> { namespace : String, tag : String, attrs : Dict.Dict String String, props : Dict.Dict String Encode.Value, events : Dict.Dict String Vdom.EventOptions, children : List Node }
        )
    -> Node
    -> Maybe Node
element path f root =
    at path
        (\n ->
            case n of
                NodeElement r ->
                    Just (NodeElement (f r))

                NodeText _ ->
                    Nothing
        )
        root


at : Path -> (Node -> Maybe Node) -> Node -> Maybe Node
at path f node =
    case path of
        [] ->
            f node

        index :: rest ->
            case node of
                NodeElement r ->
                    case List.head (List.drop index r.children) of
                        Just child ->
                            at rest f child
                                |> Maybe.map
                                    (\updated ->
                                        NodeElement
                                            { r
                                                | children =
                                                    List.indexedMap
                                                        (\i c ->
                                                            if i == index then
                                                                updated

                                                            else
                                                                c
                                                        )
                                                        r.children
                                            }
                                    )

                        Nothing ->
                            Nothing

                NodeText _ ->
                    Nothing
