defmodule Membrane.Element.IVF.VP9 do
  @moduledoc false
  use Membrane.Filter
  use Membrane.Log

  alias Membrane.{Buffer, Time, RemoteStream}
  alias Membrane.Caps.VP9

  def_options width: [spec: [integer], description: "width of frame"],
              height: [spec: [integer], description: "height of frame"],
              scale: [spec: [integer], default: 1, description: "scale"],
              rate: [spec: [integer], default: 1_000_000, description: "rate"]

  def_input_pad :input,
    caps: {RemoteStream, content_format: VP9, type: :packetized},
    demand_unit: :buffers

  def_output_pad :output, caps: :any

  use Ratio

  defmodule State do
    @moduledoc false
    defstruct [:width, :height, :timebase, framecount: 0, header_sent?: false]
  end

  @impl true
  def handle_init(options) do
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
        _ctx,
        %State{header_sent?: false} = state
      ) do
    ivf_frame =
      create_ivf_header(state.width, state.height, state.timebase) <>
        create_ivf_frame_header(byte_size(vp9_frame), timestamp, state.timebase) <> vp9_frame

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
      create_ivf_frame_header(byte_size(vp9_frame), timestamp, state.timebase) <> vp9_frame

    {{:ok, buffer: {:output, %Buffer{buffer | payload: ivf_frame}}, redemand: :output}, state}
  end

  # IVF Frame Header:
  # bytes 0-3    size of frame in bytes (not including the 12-byte header)
  # bytes 4-11   64-bit presentation timestamp
  # bytes 12..   frame data

  # Function firstly calculat
  # calculating ivf timestamp from membrane timestamp(timebase for membrane timestamp is nanosecod, and timebase for ivf is passed in options)

  defp create_ivf_frame_header(size, timestamp, timebase) do
    ivf_timestamp = timestamp / (timebase * Time.second())
    # conversion to little-endian binary stirngs
    size_le = String.reverse(<<size::32>>)
    timestamp_le = String.reverse(<<Ratio.floor(ivf_timestamp)::64>>)

    size_le <> timestamp_le
  end

  # IVF Header:
  # bytes 0-3    signature: 'DKIF'
  # bytes 4-5    version (should be 0)
  # bytes 6-7    length of header in bytes
  # bytes 8-11   codec FourCC (e.g., 'VP80')
  # bytes 12-13  width in pixels
  # bytes 14-15  height in pixels
  # bytes 16-23  time base denominator (rate)
  # bytes 20-23  time base numerator (scale)
  # bytes 24-27  number of frames in file
  # bytes 28-31  unused

  defp create_ivf_header(width, height, timebase) do
    %Ratio{denominator: rate, numerator: scale} = timebase

    signature = "DKIF"
    version = <<0, 0>>
    # note it's little endian
    length_of_header = <<32, 0>>
    codec_four_cc = "VP90"
    # conversion to little-endian binary stirngs
    width_le = String.reverse(<<width::16>>)
    height_le = String.reverse(<<height::16>>)
    rate_le = String.reverse(<<rate::32>>)
    scale_le = String.reverse(<<scale::32>>)

    # field is not used so we set it's value to 0
    frame_count = <<0::32>>
    unused = <<0::32>>

    signature <>
      version <>
      length_of_header <>
      codec_four_cc <>
      width_le <>
      height_le <>
      rate_le <>
      scale_le <>
      frame_count <>
      unused
  end
end
