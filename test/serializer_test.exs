defmodule Membrane.Element.IVF.VP9Test do
  use ExUnit.Case
  use Ratio

  import Membrane.Testing.Assertions

  alias Membrane.{Testing, RemoteStream, Buffer}
  alias Membrane.Element.IVF
  alias Membrane.VP9

  @fixtures_dir "./test/fixtures/"
  @results_dir "./test/results/"

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      sink =
        if options.to_file?,
          do: %Membrane.File.Sink{location: options.result_file},
          else: Testing.Sink

      spec = %ParentSpec{
        children: [
          ivf_serializer: %IVF.Serializer{width: 1080, height: 720, rate: 30},
          source: %Testing.Source{
            output: Testing.Source.output_from_buffers(options.buffers),
            caps: %RemoteStream{content_format: VP9, type: :packetized}
          },
          sink: sink
        ],
        links: [
          link(:source) |> to(:ivf_serializer) |> to(:sink)
        ]
      }

      {{:ok, spec: spec}, %{}}
    end

    @impl true
    def handle_notification(_notification, _child, _ctx, state) do
      {:ok, state}
    end
  end

  # example vp9 frame - just a random bitstring
  @frame <<128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128,
           128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128>>

  @doc """
  This test checks if ivf element correctly prepares file header and
  correctly calculates timestamp in frame header.
  """
  test "appends headers correctly" do
    buffer_1 = %Buffer{payload: @frame, metadata: %{timestamp: 0}}
    buffer_2 = %Buffer{payload: @frame, metadata: %{timestamp: 100_000_000 <|> 3}}

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipeline,
        custom_args: %{
          to_file?: false,
          buffers: [buffer_1, buffer_2]
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    assert_start_of_stream(pipeline, :sink)

    assert_sink_buffer(pipeline, :sink, ivf_buffer)

    <<file_header::binary-size(32), frame_header::binary-size(12), _frame::binary()>> =
      ivf_buffer.payload

    <<signature::binary-size(4), version::binary-size(2), length_of_header::binary-size(2),
      four_cc::binary-size(4), width::binary-size(2), height::binary-size(2),
      time_base_denominator::binary-size(4), time_base_numerator::binary-size(4),
      number_of_frames::binary-size(4), _unused::binary-size(4)>> = file_header

    assert signature == "DKIF"
    assert version == <<0::16>>
    assert length_of_header == <<32::16-little>>
    assert four_cc == "VP90"
    assert width == <<1080::16-little>>
    assert height == <<720::16-little>>
    assert time_base_denominator == <<30::32-little>>
    assert time_base_numerator == <<1::32-little>>
    assert number_of_frames == <<0::32-little>>

    <<size_of_frame::binary-size(4), timestamp::binary-size(8)>> = frame_header
    assert size_of_frame == <<byte_size(@frame)::32-little>>
    assert timestamp == <<0::64>>

    assert_sink_buffer(pipeline, :sink, ivf_buffer)

    <<frame_header::binary-size(12), _frame::binary()>> = ivf_buffer.payload
    <<size_of_frame::binary-size(4), timestamp::binary-size(8)>> = frame_header

    assert size_of_frame == <<byte_size(@frame)::32-little>>

    # timestamp equal to 1 is expected because buffer timestamp is 10^8/3
    # and ivf timebase is 1/30:
    # x * 1/30 [s] = 10^8/3 * 10^(-9) [s] //*30/s
    # x = 30 * 1/30 * [s/s] = 1
    assert timestamp == <<1::64-little>>

    assert_end_of_stream(pipeline, :sink)

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

  test "serialize real vp9 buffers" do
    buffers = File.read!(@fixtures_dir <> "capture.dump") |> :erlang.binary_to_term()

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipeline,
        custom_args: %{
          to_file?: true,
          result_file: @results_dir <> "result.ivf",
          buffers: buffers
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    assert_start_of_stream(pipeline, :sink)

    assert_end_of_stream(pipeline, :sink)

    assert File.read!(@results_dir <> "result.ivf") ==
             File.read!(@fixtures_dir <> "input_vp9.ivf")

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end
end
