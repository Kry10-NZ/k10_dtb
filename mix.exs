defmodule K10.DTB.MixProject do
  use Mix.Project

  def project do
    [
      app: :k10_dtb,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    []
  end
end
