defmodule Membrane.IVF.Headers do
  @moduledoc false

  alias Membrane.{VP8, VP9}

  @signature "DKIF"
  @version 0
  @header_length 32

  defmodule FileHeader do
    @moduledoc """
    A struct representing IVF file header
    """
    @type t :: %__MODULE__{
            four_cc: String.t(),
            width: non_neg_integer(),
            height: non_neg_integer(),
            timebase: Ratio.t(),
            frame_count: non_neg_integer()
          }

    @enforce_keys [
      :four_cc,
      :width,
      :height,
      :timebase,
      :frame_count
    ]
    defstruct @enforce_keys
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
    ivf_timestamp = Membrane.Time.divide_by_timebase(timestamp, Membrane.Time.seconds(timebase))
    # conversion to little-endian binary strings
    size_le = <<size::32-little>>
    timestamp_le = <<ivf_timestamp::64-little>>

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
  @spec create_ivf_header(
          non_neg_integer(),
          non_neg_integer(),
          Ratio.t(),
          non_neg_integer(),
          any()
        ) :: binary()
  def create_ivf_header(width, height, timebase, frame_count, stream_format) do
    codec_four_cc =
      case stream_format do
        %Membrane.RemoteStream{content_format: VP9} -> "VP90"
        %VP9{} -> "VP90"
        %Membrane.RemoteStream{content_format: VP8} -> "VP80"
        %VP8{} -> "VP80"
        _unknown -> "\0\0\0\0"
      end

    %Ratio{denominator: rate, numerator: scale} = timebase

    # signature = "DKIF"
    # version = <<0, 0>>
    # length_of_header = <<32, 0>>
    # # conversion to little-endian binary strings
    # width_le = <<width::16-little>>
    # height_le = <<height::16-little>>
    # rate_le = <<rate::32-little>>
    # scale_le = <<scale::32-little>>
    # # frame_count = <<frame_count::32>>
    # # field is not used so it is set to 0
    # unused = <<0::32>>

    # signature <>
    #   version <>
    #   length_of_header <>
    #   codec_four_cc <>
    #   width_le <>
    #   height_le <>
    #   rate_le <>
    #   scale_le <>
    #   frame_count <>
    #   unused

    <<@signature, @version::16-little, @header_length::16-little, codec_four_cc::binary-4,
      width::16-little, height::16-little, rate::32-little, scale::32-little,
      frame_count::32-little, 0::32>>
  end

  @spec parse_ivf_frame_header(binary()) ::
          {:ok, FrameHeader.t(), binary()} | {:error, :too_short}
  def parse_ivf_frame_header(payload) when byte_size(payload) < 12,
    do: {:error, :too_short}

  def parse_ivf_frame_header(<<size_of_frame::32-little, timestamp::64-little, rest::binary>>) do
    {:ok, %FrameHeader{size_of_frame: size_of_frame, timestamp: timestamp}, rest}
  end

  @spec parse_ivf_header(binary()) ::
          {:ok, FileHeader.t(), binary()} | {:error, :too_short | :invalid_data}
  def parse_ivf_header(payload) when byte_size(payload) < 32, do: {:error, :too_short}

  def parse_ivf_header(
        <<@signature, @version::16-little, @header_length::16-little, four_cc::binary-size(4),
          width::16-little, height::16-little, rate::32-little, scale::32-little,
          frame_count::32-little, _unused::32, rest::binary>>
      ) do
    if String.valid?(four_cc) do
      {:ok,
       %FileHeader{
         four_cc: four_cc,
         width: width,
         height: height,
         timebase: Ratio.new(scale, rate),
         frame_count: frame_count
       }, rest}
    else
      {:error, :invalid_data}
    end
  end
end
