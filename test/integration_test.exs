defmodule Membrane.IVF.IntegrationTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.{IVF, Testing}

  @input_video_vp8 %{path: "./test/fixtures/input_vp8.ivf", width: 1080, height: 720}
  @input_video_vp9 %{path: "./test/fixtures/input_vp9.ivf", width: 1080, height: 720}
  @results_dir "./test/results/"
  @result_file_vp8 "result_vp8.ivf"
  @result_file_vp9 "result_vp9.ivf"

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, options) do
      spec = [
        child(:file_source, %Membrane.File.Source{location: options.input.path})
        |> child(:deserializer, IVF.Deserializer)
        |> child(:serializer, %IVF.Serializer{
          width: options.input.width,
          height: options.input.height,
          timebase: {1, 30}
        })
        |> child(:file_sink, %Membrane.File.Sink{location: options.result_file})
      ]

      {[spec: spec], %{}}
    end

    @impl true
    def handle_child_notification(_notification, _child, _ctx, state) do
      {[], state}
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

    result_file = Path.join(@results_dir, result)

    pipeline =
      [
        module: TestPipeline,
        custom_args: %{
          input: input,
          result_file: result_file
        }
      ]
      |> Testing.Pipeline.start_link_supervised!()

    assert_end_of_stream(pipeline, :file_sink)

    Testing.Pipeline.terminate(pipeline)

    assert File.read!(input.path) ==
             File.read!(result_file)
  end
end
