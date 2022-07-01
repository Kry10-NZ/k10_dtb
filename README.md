# K10.DTB

Basic Devicetree Blob (also known as Flattened Devicetree) parser

## Basic usage

```elixir
{:ok, tree} = K10.DTB.parse(@blob)
{:ok, uints} = K10.DTB.get_property(tree, ["node2", "child-node1", "uint32-property"])
{:ok, strings} = K10.DTB.get_property(tree, ["node1", "child-node1", "string_list"])

K10.DTB.as_uint32s!(uints) # [1, 2, 3, 4]
K10.DTB.as_strings!(strings) # ["first string", "second string"]
```
