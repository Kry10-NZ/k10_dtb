# Copyright (c) 2022, Kry10 Limited. All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0

defmodule K10.DTB do
  @moduledoc """
  Basic Devicetree Blob (also known as Flattened Devicetree) parser
  """

  @magic 0xD00DFEED
  @fdt_byte_alignment 4

  @fdt_begin_node 0x00000001
  @fdt_end_node 0x00000002
  @fdt_prop 0x00000003
  @fdt_nop 0x00000004
  @fdt_end 0x00000009

  defmodule Header do
    @type t :: %Header{
            total_size: non_neg_integer,
            off_dt_struct: non_neg_integer,
            off_dt_strings: non_neg_integer,
            off_mem_rsvmap: non_neg_integer,
            version: non_neg_integer,
            last_comp_version: non_neg_integer,
            boot_cpuid_phys: non_neg_integer,
            size_dt_strings: non_neg_integer,
            size_dt_struct: non_neg_integer
          }

    defstruct [
      :total_size,
      :off_dt_struct,
      :off_dt_strings,
      :off_mem_rsvmap,
      :version,
      :last_comp_version,
      :boot_cpuid_phys,
      :size_dt_strings,
      :size_dt_struct
    ]
  end

  defmodule Tree do
    @type t :: %Tree{
            header: Header.t(),
            strings: binary,
            structs: list
          }
    defstruct [:header, :strings, :structs]
  end

  @doc """
  Parse a Devicetree blob
  """
  @spec parse(binary) :: {:ok, K10.DTB.Tree.t()} | {:error, :malformed_header}
  def parse(blob) do
    with {:ok, header} <- parse_header(blob),
         {:ok, strings} <- process_strings(blob, header),
         {:ok, structs} <- process_structs(blob, header, strings) do
      {:ok, %Tree{header: header, strings: strings, structs: structs}}
    end
  end

  @doc """
  Get the property from the tree with the specific path. A path can be requested with the following formats:

  * ["node2", "child-node1", "uint32-property"]
  * "node2/child-node1/uint32-property"

  The property value is a binary that might need to be converted. See `as_strings!/1` and
  `as_uint32s!/1`

  Examples:

      iex> K10.DTB.get_property(tree, "node2/child-node1/uint32-property")
      iex> K10.DTB.get_property(tree, ["node2", "child-node1", "uint32-property"]
  """
  @spec get_property(Tree.t(), [binary] | binary) :: {:ok, any} | {:error, :not_found}
  def get_property(tree, path) when is_list(path) do
    do_get_property(tree.structs, path)
  end

  def get_property(tree, path) when is_binary(path) do
    path = String.split(path, "/", trim: true)
    get_property(tree, path)
  end

  defp do_get_property(data, []), do: {:ok, data}

  defp do_get_property(data, [path | rest]) do
    case List.keyfind(data, path, 0) do
      {^path, value} -> do_get_property(value, rest)
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Given a "compatibility string", i.e. a string of the same meaning as of
  the "compatible" property in nodes of a device tree, this function will search
  for nodes in the tree who have the same string in their "compatible" property.
  """
  @spec find_compatible_nodes(Tree.t(), binary) :: [[binary]]
  def find_compatible_nodes(tree, compatible_string) do
    Enum.reduce(tree.structs, MapSet.new(), fn {key, value}, acc ->
      search_compatible_node([], key, value, acc, compatible_string)
    end)
    |> MapSet.to_list()
  end

  defp search_compatible_node(prefix, prop_name, prop_value, compatible_nodes, compatible_string) do
    cond do
      prop_name == "compatible" ->
        if compatible_string in as_strings!(prop_value) do
          MapSet.put(compatible_nodes, prefix)
        else
          compatible_nodes
        end

      is_list(prop_value) ->
        Enum.reduce(prop_value, compatible_nodes, fn {key, value}, acc ->
          search_compatible_node(prefix ++ ["#{prop_name}"], key, value, acc, compatible_string)
        end)

      true ->
        compatible_nodes
    end
  end

  @doc """
  Extract a list of strings from a property value. Raises an error
  if it fails to extract.
  """
  @spec as_strings!(any) :: [binary] | no_return()
  def as_strings!(bin) do
    loop_bin(bin, &extract_string/1)
  end

  @doc """
  Extract a list of unsigned integers from a property value. Raises
  an error if it fails to extract.
  """
  @spec as_uint32s!(any) :: [non_neg_integer] | no_return()
  def as_uint32s!(bin) do
    loop_bin(bin, &extract_uint32/1)
  end

  defp parse_header(blob) do
    case blob do
      <<
        @magic::size(32)-unsigned-integer-big,
        total_size::size(32)-unsigned-integer-big,
        off_dt_struct::size(32)-unsigned-integer-big,
        off_dt_strings::size(32)-unsigned-integer-big,
        off_mem_rsvmap::size(32)-unsigned-integer-big,
        version::size(32)-unsigned-integer-big,
        last_comp_version::size(32)-unsigned-integer-big,
        boot_cpuid_phys::size(32)-unsigned-integer-big,
        size_dt_strings::size(32)-unsigned-integer-big,
        size_dt_struct::size(32)-unsigned-integer-big,
        _rest::binary
      >> ->
        {:ok,
         %Header{
           total_size: total_size,
           off_dt_struct: off_dt_struct,
           off_dt_strings: off_dt_strings,
           off_mem_rsvmap: off_mem_rsvmap,
           version: version,
           last_comp_version: last_comp_version,
           boot_cpuid_phys: boot_cpuid_phys,
           size_dt_strings: size_dt_strings,
           size_dt_struct: size_dt_struct
         }}

      _ ->
        {:error, :malformed_header}
    end
  end

  defp process_strings(bin, header) do
    strings = binary_part(bin, header.off_dt_strings, header.size_dt_strings)
    {:ok, strings}
  end

  defp process_structs(bin, header, strings) do
    dt_structs = binary_part(bin, header.off_dt_struct, header.size_dt_struct)
    structs = extract_structs(dt_structs, strings)
    {:ok, structs}
  end

  defp loop_bin(<<>>, _f) do
    []
  end

  defp loop_bin(bin, f) do
    {res, rest} = f.(bin)
    [res | loop_bin(rest, f)]
  end

  defp extract_uint32(<<i::size(32)-unsigned-integer-big, rest::binary>>) do
    {i, rest}
  end

  defp fetch_string(strings, offset) do
    <<_head::binary-size(offset), rest::binary>> = strings
    {string, _} = extract_string(rest)
    string
  end

  defp extract_string(bin) do
    extract_string(bin, <<>>)
  end

  defp extract_string(<<>>, acc) do
    {acc, <<>>}
  end

  defp extract_string(<<0::8, rest::binary>>, acc) do
    {acc, rest}
  end

  defp extract_string(<<c::8, rest::binary>>, acc) do
    extract_string(rest, acc <> <<c>>)
  end

  defp extract_structs(bin, strings) do
    # FIXME error handling
    {<<>>, acc} = extract_structs(bin, strings, [])
    acc
  end

  defp extract_structs(binary, strings, acc) do
    case extract_struct(binary) do
      # root case
      {{:fdt_begin_node, ""}, rest} ->
        {rest, acc} = extract_structs(rest, strings, [])
        {:continue, rest, acc}

      {{:fdt_begin_node, name}, rest} ->
        {rest, nested} = extract_structs(rest, strings, [])
        {:continue, rest, List.keystore(acc, name, 0, {name, nested})}

      {{:fdt_prop, string_offset, data}, rest} ->
        name = fetch_string(strings, string_offset)

        acc = List.keystore(acc, name, 0, {name, data})
        {:continue, rest, acc}

      {:fdt_nop, rest} ->
        {:continue, rest, acc}

      {:fdt_end_node, rest} ->
        {:stop, rest, acc}

      {:fdt_end, rest} ->
        {:stop, rest, acc}
    end
    |> case do
      {:continue, rest, acc} ->
        extract_structs(rest, strings, acc)

      {:stop, rest, acc} ->
        {rest, acc}
    end
  end

  defp extract_struct(<<@fdt_begin_node::size(32)-unsigned-integer-big, rest::binary>>) do
    {name, rest} = extract_string(rest, <<>>)
    name_size = byte_size(name) + 1
    rest = align(rest, name_size, @fdt_byte_alignment)
    {{:fdt_begin_node, name}, rest}
  end

  defp extract_struct(
         <<@fdt_prop::size(32)-unsigned-integer-big, len::size(32)-unsigned-integer-big,
           nameoff::size(32)-unsigned-integer-big, rest::binary>>
       ) do
    <<value::binary-size(len), rest::binary>> = rest
    value_size = byte_size(value)
    rest = align(rest, value_size, @fdt_byte_alignment)
    {{:fdt_prop, nameoff, value}, rest}
  end

  defp extract_struct(<<@fdt_nop::size(32)-unsigned-integer-big, rest::binary>>) do
    {:fdt_nop, rest}
  end

  defp extract_struct(<<@fdt_end_node::size(32)-unsigned-integer-big, rest::binary>>) do
    {:fdt_end_node, rest}
  end

  defp extract_struct(<<@fdt_end::size(32)-unsigned-integer-big>>) do
    {:fdt_end, <<>>}
  end

  # Skip the amount of bytes needed to account for `offset`
  # in multiple of `alignment` bytes.
  #
  # Examples:
  #
  # offset=12, alignment=4 => Skip 12
  # offset=27, alignment=4 => Skip 28 bytes as next multiple of 4 after 27
  # offset=5, alignment=4 => Skip 8 bytes as next multiple of 4 after 5
  defp align(data, offset, alignment) do
    extra = div(offset + alignment - 1, alignment) * alignment - offset
    binary_part(data, extra, byte_size(data) - extra)
  end
end
