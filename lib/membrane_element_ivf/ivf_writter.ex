defmodule Membrane.Element.IVF.Writter do
  alias Membrane.Time

  use Ratio

  @codec_to_fourcc %{:VP9 => "VP90", :VP8 => "VP80"}

  # IVF Frame Header:
  # bytes 0-3    size of frame in bytes (not including the 12-byte header)
  # bytes 4-11   64-bit presentation timestamp
  # bytes 12..   frame data

  # Function firstly calculat
  # calculating ivf timestamp from membrane timestamp(timebase for membrane timestamp is nanosecod, and timebase for ivf is passed in options)

  def create_ivf_frame_header(size, timestamp, timebase) do
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

  def create_ivf_header(width, height, timebase, codec) do
    %Ratio{denominator: rate, numerator: scale} = timebase

    signature = "DKIF"
    version = <<0, 0>>
    # note it's little endian
    length_of_header = <<32, 0>>
    codec_four_cc = @codec_to_fourcc |> Map.get(codec)
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
