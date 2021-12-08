defmodule Membrane.Element.IVF.Serializer do
  @moduledoc """
  Serializes video stream into IVF format.
  """

  use Membrane.Filter
  use Membrane.Log

  alias Membrane.Element.IVF
  alias Membrane.{Buffer, RemoteStream}
  alias Membrane.{VP9, VP8}

  def_options width: [spec: [integer], default: 0, description: "width of frame"],
              height: [spec: [integer], default: 0, description: "height of frame"],
              scale: [spec: [integer], default: 1, description: "scale"],
              rate: [spec: [integer], default: 1_000_000, description: "rate"],
              frame_count: [spec: [integer], default: 0, description: "number of frames"]

  def_input_pad :input,
    caps: [
      VP8,
      VP9,
      {RemoteStream, content_format: one_of([VP8, VP9]), type: :packetized}
    ],
    demand_unit: :buffers

  def_output_pad :output, caps: :any

  defmodule State do
    @moduledoc false
    defstruct [:width, :height, :scale, :rate, :timebase, :frame_count, first_frame: true]
  end

  @impl true
  def handle_init(options) do
    use Ratio

    {:ok,
     %State{
       width: options.width,
       height: options.height,
       timebase: options.scale <|> options.rate,
       frame_count: options.frame_count,
       first_frame: true
     }}
  end

  @impl true
  def handle_caps(:input, %VP8{} = caps, _ctx, state) do
    {:ok, %State{state | height: caps.height, width: caps.width}}
  end

  @impl true
  def handle_caps(:input, %VP9{} = caps, _ctx, state) do
    {:ok, %State{state | height: caps.height, width: caps.width}}
  end

  @impl true
  def handle_caps(_pad, _caps, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, buffer, ctx, state) do
    %Buffer{payload: frame, pts: timestamp} = buffer

    ivf_frame =
      IVF.Headers.create_ivf_frame_header(byte_size(frame), timestamp, state.timebase) <>
        frame

    ivf_file_header =
      if state.first_frame do
        if state.width == 0 or state.height == 0,
          do:
            IO.warn(
              "Serializing stream to IVF without width or height. These parameters can be passed via options or caps"
            )

        IVF.Headers.create_ivf_header(
          state.width,
          state.height,
          state.timebase,
          state.frame_count,
          ctx.pads.input.caps
        )
      end

    ivf_buffer = (ivf_file_header || "") <> ivf_frame

    {{:ok, buffer: {:output, %Buffer{buffer | payload: ivf_buffer}}, redemand: :output},
     %State{state | first_frame: false}}
  end
end
