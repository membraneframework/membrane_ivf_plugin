defmodule Membrane.Element.IVF.Headers do
  @moduledoc false

  use Ratio

  alias Membrane.Time
  alias Membrane.{VP9, VP8}

  defmodule FileHeader do
    @moduledoc """
    A struct representing IVF file header
    """
    @type t :: %__MODULE__{
            signature: String.t(),
            version: non_neg_integer(),
            length_of_header: non_neg_integer(),
            four_cc: String.t(),
            width: non_neg_integer(),
            height: non_neg_integer(),
            rate: non_neg_integer(),
            scale: non_neg_integer(),
            frame_count: non_neg_integer()
          }

    defstruct [
      :signature,
      :version,
      :length_of_header,
      :four_cc,
      :width,
      :height,
      :rate,
      :scale,
      :frame_count
    ]
  end

  defmodule FrameHeader do
    @moduledoc """
    A struct representing IVF frame header
    """

    @type t :: %__MODULE__{
            size_of_frame: non_neg_integer(),
            timestamp: non_neg_integer()
          }
    defstruct [:size_of_frame, :timestamp]
  end

  # IVF Frame Header:
  # bytes 0-3    size of frame in bytes (not including the 12-byte header)
  # bytes 4-11   64-bit presentation timestamp
  # bytes 12..   frame data

  # Function firstly calculate
  # calculating ivf timestamp from membrane timestamp(timebase for membrane timestamp is nanosecond, and timebase for ivf is passed in options)

  @spec create_ivf_frame_header(integer, number | Ratio.t(), number | Ratio.t()) :: binary
  def create_ivf_frame_header(size, timestamp, timebase) do
    ivf_timestamp = timestamp / (timebase * Time.second())
    # conversion to little-endian binary strings
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
  # bytes 16-19  time base denominator (rate)
  # bytes 20-23  time base numerator (scale)
  # bytes 24-27  number of frames in file
  # bytes 28-31  unused
  @spec create_ivf_header(integer, integer, Ratio.t(), integer, any) :: binary
  def create_ivf_header(width, height, timebase, frame_count, caps) do
    codec_four_cc =
      case caps do
        %Membrane.RemoteStream{content_format: VP9} -> "VP90"
        %Membrane.RemoteStream{content_format: VP8} -> "VP80"
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
    frame_count = <<frame_count::32>>
    # field is not used so it is set to 0
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

  @spec parse_ivf_frame_header(binary()) ::
          {:ok, FrameHeader.t(), binary()} | {:error_too_short, binary()}
  def parse_ivf_frame_header(payload) when byte_size(payload) < 12,
    do: {:error_too_short, payload}

  def parse_ivf_frame_header(<<size_of_frame::32-little, timestamp::64-little, rest::binary()>>) do
    {:ok, %FrameHeader{size_of_frame: size_of_frame, timestamp: timestamp}, rest}
  end

  @spec parse_ivf_header(binary()) ::
          {:ok, FileHeader.t(), binary()} | {:error_too_short | :error_invalid_data, binary()}
  def parse_ivf_header(payload) when byte_size(payload) < 32, do: {:error_too_short, payload}

  def parse_ivf_header(
        <<signature::binary-size(4), version::16-little, length_of_header::16-little,
          four_cc::binary-size(4), width::16-little, height::16-little, rate::32-little,
          scale::32-little, frame_count::32-little, _unused::32, rest::binary()>> = payload
      ) do
    if String.valid?(signature) and String.valid?(four_cc) do
      {:ok,
       %FileHeader{
         signature: signature,
         version: version,
         length_of_header: length_of_header,
         four_cc: four_cc,
         width: width,
         height: height,
         rate: rate,
         scale: scale,
         frame_count: frame_count
       }, rest}
    else
      {:error_invalid_data, payload}
    end
  end
end
