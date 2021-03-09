defmodule Membrane.Element.IVF.Headers do
  @moduledoc false

  use Ratio

  alias Membrane.Time
  alias Membrane.Caps.VP9
  alias Membrane.Caps.VP8
  # IVF Frame Header:
  # bytes 0-3    size of frame in bytes (not including the 12-byte header)
  # bytes 4-11   64-bit presentation timestamp
  # bytes 12..   frame data

  # Function firstly calculat
  # calculating ivf timestamp from membrane timestamp(timebase for membrane timestamp is nanosecod, and timebase for ivf is passed in options)

  @spec create_ivf_frame_header(integer, number | Ratio.t(), number | Ratio.t()) :: binary
  def create_ivf_frame_header(size, timestamp, timebase) do
    ivf_timestamp = timestamp / (timebase * Time.second())
    # conversion to little-endian binary stirngs
    size_le = <<size::32-little>>
    timestamp_le = <<Ratio.floor(ivf_timestamp)::64-little>>

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

  @spec create_ivf_header(integer, integer, Ratio.t(), any) :: binary
  def create_ivf_header(width, height, timebase, caps) do
    codec_four_cc =
      case caps do
        %Membrane.RemoteStream{content_format: VP9} -> "VP90"
        %Membrane.RemoteStream{content_format: VP8} -> "VP80"
        _unknown -> "\0\0\0\0"
      end

    %Ratio{denominator: rate, numerator: scale} = timebase

    version = 0
    length_of_header = 32
    # frame count is not used so it is set to 0
    frame_count = 0
    <<"DKIF", version::16-little, length_of_header::16-little, codec_four_cc::binary, width::16-little, height::16-little, rate::32-little, scale::32-little, frame_count::32-little, 0::32-little>>
  end
end
