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
            strings: %{(offset :: non_neg_integer()) => binary()},
            structs: map
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
    case get_in(tree.structs, path) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  def get_property(tree, path) when is_binary(path) do
    path = String.split(path, "/", trim: true)
    get_property(tree, path)
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
    dt_strings = binary_part(bin, header.off_dt_strings, header.size_dt_strings)
    strings = extract_strings(dt_strings)
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

  defp extract_strings(dt_strings) do
    # return map of offest -> string
    extract_strings(dt_strings, 0, %{})
  end

  defp extract_strings(<<>>, _count, result) do
    result
  end

  defp extract_strings(strings, count, result) do
    {res, rest} = extract_string(strings)
    result = Map.put_new(result, count, res)
    extract_strings(rest, count + byte_size(res) + 1, result)
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
    {<<>>, acc} = extract_structs(bin, strings, %{})
    acc
  end

  defp extract_structs(binary, strings, acc) do
    case extract_struct(binary) do
      # root case
      {{:fdt_begin_node, ""}, rest} ->
        {rest, acc} = extract_structs(rest, strings, %{})
        {:continue, rest, acc}

      {{:fdt_begin_node, name}, rest} ->
        {rest, nested} = extract_structs(rest, strings, %{})
        {:continue, rest, Map.put_new(acc, name, nested)}

      {{:fdt_prop, string_offset, data}, rest} ->
        name = Map.fetch!(strings, string_offset)
        acc = Map.put_new(acc, name, data)
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
    extra = align(name_size, @fdt_byte_alignment) - name_size
    rest = eat_nulls(rest, extra)
    {{:fdt_begin_node, name}, rest}
  end

  defp extract_struct(
         <<@fdt_prop::size(32)-unsigned-integer-big, len::size(32)-unsigned-integer-big,
           nameoff::size(32)-unsigned-integer-big, rest::binary>>
       ) do
    <<value::binary-size(len), rest::binary>> = rest
    value_size = byte_size(value)
    extra = align(value_size, @fdt_byte_alignment) - value_size
    rest = eat_nulls(rest, extra)
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

  defp eat_nulls(rest, 0) do
    rest
  end

  defp eat_nulls(<<0::8, rest::binary>>, cnt) do
    eat_nulls(rest, cnt - 1)
  end

  # smallest v >= n such that v is a multiple of k
  defp align(n, k) do
    div(n + k - 1, k) * k
  end
end
