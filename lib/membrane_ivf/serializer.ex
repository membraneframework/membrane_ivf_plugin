defmodule Membrane.IVF.Serializer do
  @moduledoc """
  Serializes video stream into IVF format.
  """

  use Membrane.Filter
  use Numbers, overload_operators: true

  alias Membrane.IVF.Headers
  alias Membrane.{Buffer, File, IVF, RemoteStream}
  alias Membrane.{VP8, VP9}

  @frame_count_file_position 24

  def_options width: [
                spec: non_neg_integer() | nil,
                default: nil,
                description: """
                Width of a frame, needed if not provided with stream format. If it's not specified either in this option or the stream format, the element will crash.
                """
              ],
              height: [
                spec: non_neg_integer() | nil,
                default: nil,
                description: """
                Height of a frame, needed if not provided with stream format. If it's not specified either in this option or the stream format, the element will crash.
                """
              ],
              timebase: [
                spec: {non_neg_integer(), pos_integer()},
                default: {1, 1_000_000_000},
                description: """
                Timebase for the timestamps added to the frames
                """
              ],
              frame_count: [
                spec: non_neg_integer() | :dynamic,
                default: :dynamic,
                description: """
                Number of frames in the stream. If set to `:dynamic` the frames will be counted and
                a `Membrane.File.SeekSinkEvent` will be sent on end of stream to insert this value in
                the file header. In that case the element MUST be used along with `Membrane.File.Sink`
                or any other sink that can handle `Membrane.File.SeekSinkEvent`.
                """
              ]

  def_input_pad :input,
    accepted_format:
      any_of(
        %RemoteStream{content_format: format, type: :packetized} when format in [VP9, VP8],
        VP8,
        VP9
      )

  def_output_pad :output, accepted_format: _any

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            width: non_neg_integer() | nil,
            height: non_neg_integer() | nil,
            timebase: Ratio.t(),
            frame_count: non_neg_integer() | :dynamic
          }

    @enforce_keys [:width, :height, :timebase, :frame_count]
    defstruct @enforce_keys ++
                [
                  frames_processed: 0
                ]
  end

  @impl true
  def handle_init(_ctx, options) do
    {timebase_num, timebase_den} = options.timebase

    {[],
     %State{
       width: options.width,
       height: options.height,
       timebase: Ratio.new(timebase_num, timebase_den),
       frame_count: options.frame_count
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %Membrane.RemoteStream{type: :packetized, content_format: IVF}}],
     state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {width, height} = get_frame_dimensions(stream_format, state)

    frame_count = if state.frame_count == :dynamic, do: 0, else: state.frame_count

    ivf_header =
      Headers.create_ivf_header(width, height, state.timebase, frame_count, stream_format)

    {[buffer: {:output, %Buffer{payload: ivf_header}}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    %Buffer{payload: frame, pts: timestamp} = buffer

    ivf_frame =
      Headers.create_ivf_frame_header(byte_size(frame), timestamp, state.timebase) <>
        frame

    {[buffer: {:output, %Buffer{buffer | payload: ivf_frame}}],
     %{state | frames_processed: state.frames_processed + 1}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    actions =
      if state.frame_count == :dynamic do
        [
          event: {:output, %File.SeekSinkEvent{position: @frame_count_file_position}},
          buffer: {:output, %Buffer{payload: <<state.frames_processed::32-little>>}},
          end_of_stream: :output
        ]
      else
        [end_of_stream: :output]
      end

    {actions, state}
  end

  @spec get_frame_dimensions(RemoteStream.t() | VP8.t() | VP9.t(), State.t()) ::
          {width :: non_neg_integer(), height :: non_neg_integer()}
  defp get_frame_dimensions(input_stream_format, state) do
    case input_stream_format do
      %RemoteStream{} ->
        {
          state.width || raise("Width not provided"),
          state.height || raise("Height not provided")
        }

      %{width: width, height: height} ->
        {width, height}
    end
  end
end
