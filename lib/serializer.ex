defmodule Membrane.Element.IVF.Serializer do
  @moduledoc """
  Serializes video stream into IVF format.
  """

  use Membrane.Filter

  alias Membrane.Element.IVF
  alias Membrane.{Buffer, RemoteStream}
  alias Membrane.{VP8, VP9}

  def_options width: [spec: [integer], description: "width of frame"],
              height: [spec: [integer], description: "height of frame"],
              scale: [spec: [integer], default: 1, description: "scale"],
              rate: [spec: [integer], default: 1_000_000, description: "rate"],
              frame_count: [spec: [integer], default: 0, description: "number of frames"]

  def_input_pad :input,
    accepted_format:
      %RemoteStream{content_format: format, type: :packetized} when format in [VP9, VP8],
    flow_control: :manual,
    demand_unit: :buffers

  def_output_pad :output, flow_control: :manual, accepted_format: _any

  defmodule State do
    @moduledoc false
    defstruct [:width, :height, :timebase, :first_frame, :frame_count]
  end

  @impl true
  def handle_init(_ctx, options) do
    use Numbers, overload_operators: true

    {[],
     %State{
       width: options.width,
       height: options.height,
       timebase: Ratio.new(options.scale, options.rate),
       frame_count: options.frame_count,
       first_frame: true
     }}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {[demand: {:input, size}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    %Buffer{payload: frame, pts: timestamp} = buffer

    ivf_frame =
      IVF.Headers.create_ivf_frame_header(byte_size(frame), timestamp, state.timebase) <>
        frame

    ivf_file_header =
      if state.first_frame,
        do:
          IVF.Headers.create_ivf_header(
            state.width,
            state.height,
            state.timebase,
            state.frame_count,
            ctx.pads.input.stream_format
          )

    ivf_buffer = (ivf_file_header || "") <> ivf_frame

    {[buffer: {:output, %Buffer{buffer | payload: ivf_buffer}}, redemand: :output],
     %State{state | first_frame: false}}
  end
end
