defmodule Membrane.Element.IVF.Serializer do
  @moduledoc false
  use Membrane.Filter
  use Membrane.Log

  alias Membrane.Element.IVF
  alias Membrane.{Buffer, RemoteStream}
  alias Membrane.VP9
  alias Membrane.VP8

  def_options width: [spec: integer, description: "width of frame"],
              height: [spec: integer, description: "height of frame"],
              scale: [spec: integer, default: 1, description: "scale"],
              rate: [spec: integer, default: 1_000_000, description: "rate"]

  def_input_pad :input,
    caps: {RemoteStream, content_format: one_of([VP9, VP8]), type: :packetized},
    demand_unit: :buffers

  def_output_pad :output, caps: :any

  defmodule State do
    @moduledoc false
    defstruct [:width, :height, :timebase]
  end

  @impl true
  def handle_init(options) do
    use Ratio

    {:ok,
     %State{
       width: options.width,
       height: options.height,
       timebase: options.scale <|> options.rate
     }}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, buffer, ctx, state) do
    %Buffer{payload: frame, metadata: %{timestamp: timestamp}} = buffer

    ivf_frame =
      IVF.Headers.create_ivf_frame_header(byte_size(frame), timestamp, state.timebase) <>
        frame

    ivf_file_header =
      if timestamp == 0,
        do:
          IVF.Headers.create_ivf_header(
            state.width,
            state.height,
            state.timebase,
            ctx.pads.input.caps
          )

    ivf_buffer = (ivf_file_header || "") <> ivf_frame
    {{:ok, buffer: {:output, %Buffer{buffer | payload: ivf_buffer}}, redemand: :output}, state}
  end
end
