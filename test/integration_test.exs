defmodule Membrane.Element.IVF.IntegrationTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Element.IVF
  alias Membrane.{Testing}

  @input_video_vp8 %{path: "./test/fixtures/input_vp8.ivf", width: 1080, height: 720}
  @input_video_vp9 %{path: "./test/fixtures/input_vp9.ivf", width: 1080, height: 720}
  @results_dir "./test/results/"
  @result_file_vp8 "result_vp8.ivf"
  @result_file_vp9 "result_vp9.ivf"

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(options) do
      spec = %ParentSpec{
        children: [
          file_source: %Membrane.File.Source{location: options.input.path},
          deserializer: IVF.Deserializer,
          serializer: IVF.Serializer,
          file_sink: %Membrane.File.Sink{location: options.result_file}
        ],
        links: [
          link(:file_source) |> to(:deserializer) |> to(:serializer) |> to(:file_sink)
        ]
      }

      {{:ok, spec: spec}, %{}}
    end

    @impl true
    def handle_notification(_notification, _child, _ctx, state) do
      {:ok, state}
    end
  end

  test "deserializing vp8 ivf and serializing back" do
    test_stream(@input_video_vp8, @result_file_vp8)
  end

  test "deserializing vp9 ivf and serializing back" do
    test_stream(@input_video_vp9, @result_file_vp9)
  end

  defp test_stream(input, result) do
    if !File.exists?(@results_dir) do
      File.mkdir!(@results_dir)
    end

    {:ok, pipeline} =
      %Testing.Pipeline.Options{
        module: TestPipeline,
        custom_args: %{
          input: input,
          result_file: @results_dir <> result
        }
      }
      |> Testing.Pipeline.start_link()

    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)

    assert_end_of_stream(pipeline, :file_sink)

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, _, :stopped)

    assert File.read!(input.path) ==
             File.read!(@results_dir <> result)
  end
end
