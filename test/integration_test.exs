defmodule Membrane.IVF.IntegrationTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.{IVF, Testing}

  @input_path_vp8 "./test/fixtures/input_vp8.ivf"
  @input_path_vp9 "./test/fixtures/input_vp9.ivf"
  @output_file_vp8 "output_vp8.ivf"
  @output_file_vp9 "output_vp9.ivf"

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, options) do
      spec = [
        child(:file_source, %Membrane.File.Source{location: options.input_path})
        |> child(:deserializer, IVF.Deserializer)
        |> child(:serializer, %IVF.Serializer{
          timebase: {1, 30}
        })
        |> child(:file_sink, %Membrane.File.Sink{location: options.output_path})
      ]

      {[spec: spec], %{}}
    end

    @impl true
    def handle_child_notification(_notification, _child, _ctx, state) do
      {[], state}
    end
  end

  describe "deserializing ivf and serializing back for" do
    @describetag :tmp_dir
    test "VP8", %{tmp_dir: tmp_dir} do
      test_stream(@input_path_vp8, @output_file_vp8, tmp_dir)
    end

    test "VP9", %{tmp_dir: tmp_dir} do
      test_stream(@input_path_vp9, @output_file_vp9, tmp_dir)
    end
  end

  defp test_stream(input_path, output_file, tmp_dir) do
    output_path = Path.join(tmp_dir, output_file)

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec:
          child(:file_source, %Membrane.File.Source{location: input_path})
          |> child(:deserializer, IVF.Deserializer)
          |> child(:serializer, %IVF.Serializer{
            timebase: {1, 30}
          })
          |> child(:file_sink, %Membrane.File.Sink{location: output_path})
      )

    assert_end_of_stream(pipeline, :file_sink)

    Testing.Pipeline.terminate(pipeline)

    assert File.read!(input_path) == File.read!(output_path)
  end
end
