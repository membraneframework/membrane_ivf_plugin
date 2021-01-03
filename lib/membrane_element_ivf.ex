defmodule Membrane.Element.IVF do
  @moduledoc false
  use Membrane.Filter
  use Membrane.Log

  alias Membrane.Element.IVF
  alias Membrane.{Buffer, RemoteStream}
  alias Membrane.Caps.VP9

  def_options width: [spec: [integer], description: "width of frame"],
              height: [spec: [integer], description: "height of frame"],
              scale: [spec: [integer], default: 1, description: "scale"],
              rate: [spec: [integer], default: 1_000_000, description: "rate"]

  def_input_pad :input,
    caps: {RemoteStream, content_format: one_of([VP9, :VP8]), type: :packetized},
    demand_unit: :buffers

  def_output_pad :output, caps: :any

  defmodule State do
    @moduledoc false
    defstruct [:width, :height, :timebase, framecount: 0, header_sent?: false]
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
  def handle_process(
        :input,
        %Buffer{payload: vp9_frame, metadata: %{timestamp: timestamp}} = buffer,
        ctx,
        %State{header_sent?: false} = state
      ) do
        IO.inspect(ctx)
    ivf_frame =
      IVF.Writter.create_ivf_header(state.width, state.height, state.timebase, :VP9) <>
        IVF.Writter.create_ivf_frame_header(byte_size(vp9_frame), timestamp, state.timebase) <> vp9_frame

    {{:ok, buffer: {:output, %Buffer{buffer | payload: ivf_frame}}, redemand: :output},
     %State{state | header_sent?: true}}
  end

  @impl true
  def handle_process(
        :input,
        %Buffer{payload: vp9_frame, metadata: %{timestamp: timestamp}} = buffer,
        _ctx,
        %State{header_sent?: true} = state
      ) do
    ivf_frame =
      IVF.Writter.create_ivf_frame_header(byte_size(vp9_frame), timestamp, state.timebase) <> vp9_frame

    {{:ok, buffer: {:output, %Buffer{buffer | payload: ivf_frame}}, redemand: :output}, state}
  end
end
