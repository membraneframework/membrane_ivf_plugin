defmodule Membrane.Element.IVF.Serializer do
  @moduledoc """
  Serializes video stream into IVF format.
  """

  use Membrane.Filter
  use Membrane.Log

  alias Membrane.Element.IVF
  alias Membrane.Buffer
  alias Membrane.{VP9, VP8}

  def_options scale: [spec: [integer], default: 1, description: "scale"],
              rate: [spec: [integer], default: 1_000_000, description: "rate"],
              frame_count: [spec: [integer], default: 0, description: "number of frames"]

  def_input_pad :input,
    caps: [VP9, VP8],
    demand_unit: :buffers

  def_output_pad :output, caps: :any

  defmodule State do
    @moduledoc false
    defstruct [:width, :height, :timebase, :first_frame, :frame_count]
  end

  @impl true
  def handle_init(options) do
    use Ratio

    {:ok,
     %State{
       timebase: options.scale <|> options.rate,
       frame_count: options.frame_count,
       first_frame: true
     }}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, state) do
    state_map = Map.from_struct(state)
    caps_map = Map.from_struct(caps)
    merged = Map.merge(state_map, caps_map)
    new_state = struct(State, merged)

    {{:ok, caps: {:output, caps}}, new_state}
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
      unless is_nil(state.width) or is_nil(state.height) do
        if state.first_frame,
          do:
            IVF.Headers.create_ivf_header(
              state.width,
              state.height,
              state.timebase,
              state.frame_count,
              ctx.pads.input.caps
            )
      else
        raise "IVF.Serializer requires `width` and `height` to be passed via caps."
      end

    ivf_buffer = (ivf_file_header || "") <> ivf_frame

    {{:ok, buffer: {:output, %Buffer{buffer | payload: ivf_buffer}}, redemand: :output},
     %State{state | first_frame: false}}
  end
end
