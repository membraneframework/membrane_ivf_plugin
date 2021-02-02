defmodule Membrane.Element.IVF.Headers do
  @moduledoc false

  use Ratio

  alias Membrane.Time
  alias Membrane.Caps.VP9
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
        %Membrane.RemoteStream{content_format: :VP8} -> "VP80"
        _unknown -> "\0\0\0\0"
      end

    %Ratio{denominator: rate, numerator: scale} = timebase

    signature = "DKIF"
    version = <<0, 0>>
    length_of_header = <<32, 0>>
    # conversion to little-endian binary stirngs
    width_le = <<width::16-little>>
    height_le = <<height::16-little>>
    rate_le = <<rate::32-little>>
    scale_le = <<scale::32-little>>

    # field is not used so it is set to 0
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
