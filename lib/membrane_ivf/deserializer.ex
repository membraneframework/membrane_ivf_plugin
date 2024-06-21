defmodule Membrane.IVF.Deserializer do
  @moduledoc """
  Deserializer is capable of converting stream representing video in IVF format
  into stream of Membrane.Buffer's with video frames with correct timestamps in
  Membrane timebase (it is 1 nanosecond = 1/(10^9)[s])
  """
  use Membrane.Filter
  use Numbers, overload_operators: true

  alias Membrane.IVF.Headers
  alias Membrane.IVF.Headers.FrameHeader
  alias Membrane.{Buffer, IVF, Time}
  alias Membrane.{VP8, VP9}

  def_input_pad :input,
    accepted_format: %Membrane.RemoteStream{content_format: fmt} when fmt in [IVF, nil]

  def_output_pad :output,
    accepted_format: any_of(VP8, VP9)

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            timebase: Ratio.t(),
            frame_acc: binary(),
            beginning_of_stream: boolean()
          }

    defstruct timebase: nil,
              frame_acc: <<>>,
              beginning_of_stream: true
  end

  @impl true
  def handle_init(_ctx, _options) do
    {[], %State{}}
  end

  @impl true
  def handle_stream_format(_pad, _stream_format, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %State{beginning_of_stream: true} = state) do
    state = %State{state | frame_acc: state.frame_acc <> buffer.payload}

    with {:ok, file_header, rest} <- Headers.parse_ivf_header(state.frame_acc),
         {:ok, buffer, rest} <- get_buffer(rest, file_header.timebase) do
      stream_format =
        case file_header.four_cc do
          "VP90" -> %VP9{width: file_header.width, height: file_header.height}
          "VP80" -> %VP8{width: file_header.width, height: file_header.height}
        end

      {[stream_format: {:output, stream_format}, buffer: {:output, buffer}],
       %State{
         frame_acc: rest,
         beginning_of_stream: false,
         timebase: file_header.timebase
       }}
    else
      {:error, :too_short} ->
        {[], state}

      {:error, reason} ->
        raise "Deserialization of IVF failed with reason: `#{inspect(reason)}`"
    end
  end

  def handle_buffer(:input, buffer, _ctx, state) do
    state = %State{state | frame_acc: state.frame_acc <> buffer.payload}

    case flush_acc(state, []) do
      {:ok, buffers, state} ->
        {[buffer: {:output, buffers}], state}

      {:error, :too_short} ->
        {[], state}
    end
  end

  defp flush_acc(state, buffers) do
    case get_buffer(state.frame_acc, state.timebase) do
      {:ok, buffer, rest} -> flush_acc(%State{state | frame_acc: rest}, [buffer | buffers])
      {:error, :too_short} when buffers != [] -> {:ok, Enum.reverse(buffers), state}
      error -> error
    end
  end

  defp get_buffer(payload, timebase) do
    with {:ok, %FrameHeader{size_of_frame: size_of_frame, timestamp: timestamp}, rest} <-
           Headers.parse_ivf_frame_header(payload),
         <<frame::binary-size(size_of_frame), rest::binary>> <- rest do
      timestamp = Time.seconds(timestamp * timebase)
      {:ok, %Buffer{pts: timestamp, payload: frame}, rest}
    else
      _error -> {:error, :too_short}
    end
  end
end
