defmodule Membrane.Element.IVF.Deserializer do
  @moduledoc """
  Deserializer is capable of converting stream representing video in IVF format
  into stream of Membrane.Buffer's with video frames with correct timestamps in
  Membrane timebase (it is 1 nanosecond = 1/(10^9)[s])
  """
  use Membrane.Filter
  use Ratio

  alias Membrane.{Time, Buffer}
  alias Membrane.{VP9, VP8}
  alias Membrane.Element.IVF.Headers
  alias Membrane.Element.IVF.Headers.FrameHeader

  def_input_pad :input, caps: :any, demand_unit: :buffers

  def_output_pad :output,
    caps: [VP9, VP8]

  defmodule State do
    @moduledoc false

    @doc """
    frame_acc is tuple of {bytes_left_to_accumulate, accumulated_binary}
    When bytes_left_to_accumulate is equal to 0 it means that whole frame has been accumulated
    """
    defstruct [:timebase, frame_acc: <<>>, start_of_stream?: true]
  end

  @impl true
  def handle_init(_options) do
    {:ok, %State{}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, %State{start_of_stream?: true} = state) do
    state = %State{state | frame_acc: state.frame_acc <> buffer.payload}

    with {:ok, file_header, rest} <- Headers.parse_ivf_header(state.frame_acc),
         {:ok, buffer, rest} <- get_buffer(rest, file_header.scale <|> file_header.rate) do
      caps =
        case file_header.four_cc do
          "VP90" ->
            %VP9{
              width: file_header.width,
              height: file_header.height,
              scale: file_header.scale,
              rate: file_header.rate
            }

          "VP80" ->
            %VP8{
              width: file_header.width,
              height: file_header.height,
              scale: file_header.scale,
              rate: file_header.rate
            }
        end

      {{:ok, caps: {:output, caps}, buffer: {:output, buffer}, redemand: :output},
       %State{
         frame_acc: rest,
         start_of_stream?: false,
         timebase: file_header.scale <|> file_header.rate
       }}
    else
      :error_too_short ->
        {{:ok, redemand: :output}, state}

      _error ->
        {:ok, %State{}}
    end
  end

  def handle_process(:input, buffer, _ctx, state) do
    state = %State{state | frame_acc: state.frame_acc <> buffer.payload}

    {:ok, buffers, state} = flush_acc(state, [])

    {{:ok, buffer: {:output, buffers}, redemand: :output}, state}
  end

  defp flush_acc(state, buffers) do
    case get_buffer(state.frame_acc, state.timebase) do
      {:ok, buffer, rest} -> flush_acc(%State{state | frame_acc: rest}, [buffer | buffers])
      _error -> {:ok, Enum.reverse(buffers), state}
    end
  end

  defp get_buffer(payload, timebase) do
    with {:ok, %FrameHeader{size_of_frame: size_of_frame, timestamp: timestamp}, rest} <-
           Headers.parse_ivf_frame_header(payload),
         <<frame::binary-size(size_of_frame), rest::binary()>> <- rest do
      timestamp = timestamp * (timebase * Time.second())
      {:ok, %Buffer{pts: timestamp, payload: frame}, rest}
    else
      _error -> :error_too_short
    end
  end
end
