# Copyright (c) 2022, Kry10 Limited. All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0

defmodule K10.DTBTest do
  use ExUnit.Case, async: true
  alias K10.DTB.Tree

  @blob File.read!("test/support/manifest.dtb")
  @malformed_blob File.read!("test/support/malformed_manifest.dtb")

  describe "parse/1" do
    test "basic parsing" do
      assert {:ok, %Tree{} = tree} = K10.DTB.parse(@blob)
      assert %K10.DTB.Header{total_size: 365} = tree.header
      assert byte_size(tree.strings) == tree.header.size_dt_strings

      {:ok, uints} = K10.DTB.get_property(tree, ["node2", "child-node1", "uint32-property"])
      {:ok, strings} = K10.DTB.get_property(tree, ["node1", "child-node1", "string_list"])

      assert K10.DTB.as_uint32s!(uints) == [1, 2, 3, 4]
      assert K10.DTB.as_strings!(strings) == ["first string", "second string"]
    end

    test "parsing padding with non-null" do
      assert {:ok, %Tree{} = tree} =
               File.read!("test/support/non_null_padding_manifest.dtb")
               |> K10.DTB.parse()

      {:ok, strings} = K10.DTB.get_property(tree, ["test", "something"])

      assert K10.DTB.as_strings!(strings) == ["other"]
    end

    test "malformed header" do
      assert {:error, :malformed_header} = K10.DTB.parse(@malformed_blob)
    end
  end

  describe "get_property/2" do
    setup do
      assert {:ok, tree} = K10.DTB.parse(@blob)
      %{tree: tree}
    end

    test "path with /", %{tree: tree} do
      {:ok, uints} = K10.DTB.get_property(tree, "node2/child-node1/uint32-property")
      {:ok, strings} = K10.DTB.get_property(tree, "node1/child-node1/string_list")

      assert K10.DTB.as_uint32s!(uints) == [1, 2, 3, 4]
      assert K10.DTB.as_strings!(strings) == ["first string", "second string"]
    end

    test "path for a node", %{tree: tree} do
      assert {:ok,
              [
                {"max_number", _},
                {"number", _},
                {"string_list", _}
              ]} = K10.DTB.get_property(tree, ["node1", "child-node1"])
    end
  end

  describe "find_compatible_nodes/2" do
    setup do
      assert {:ok, tree} = K10.DTB.parse(@blob)
      %{tree: tree}
    end

    test "search for node that exists", %{tree: tree} do
      compatible_nodes = K10.DTB.find_compatible_nodes(tree, "test_device")
      assert compatible_nodes == [["node2", "child-node1"]]
    end

    test "search for node that does not exist", %{tree: tree} do
      compatible_nodes = K10.DTB.find_compatible_nodes(tree, "non_existent_device")
      assert compatible_nodes == []
    end
  end
end
