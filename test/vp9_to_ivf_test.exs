defmodule Membrane.Element.IVF.VP9Test do
  use ExUnit.Case
  use Ratio

  alias Membrane.Buffer
  alias Membrane.Element.IVF

  # example vp9 frame - just a random bitstring
  @vp9_frame <<128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128,
               128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128>>

  @doc """
  This test checks if ivf element correctly prepares file header and
  correctly calculates timestamp in frame header.
  """
  test "appends headers correctly" do
    vp9_buffer_1 = %Buffer{payload: @vp9_frame, metadata: %{timestamp: 0}}
    vp9_buffer_2 = %Buffer{payload: @vp9_frame, metadata: %{timestamp: 100_000_000 <|> 3}}

    {:ok, ivf_element_state} = IVF.VP9.handle_init(%IVF.VP9{width: 1080, height: 720, rate: 30})

    {{:ok, buffer: {:output, ivf_buffer}, redemand: :output}, ivf_element_state} =
      IVF.VP9.handle_process(:input, vp9_buffer_1, nil, ivf_element_state)

    <<file_header::binary-size(32), frame_header::binary-size(12), vp9_frame::binary()>> =
      ivf_buffer.payload

    <<signature::binary-size(4), version::binary-size(2), length_of_header::binary-size(2),
      four_cc::binary-size(4), width::binary-size(2), height::binary-size(2),
      time_base_denominator::binary-size(4), time_base_numerator::binary-size(4),
      number_of_frames::binary-size(4), _unused::binary-size(4)>> = file_header

    # String.reverse because in IVF little-endian is used
    assert signature == "DKIF"
    assert version == <<0::16>>
    assert String.reverse(length_of_header) == <<32::16>>
    assert four_cc == "VP90"
    assert String.reverse(width) == <<1080::16>>
    assert String.reverse(height) == <<720::16>>
    assert String.reverse(time_base_denominator) == <<30::32>>
    assert String.reverse(time_base_numerator) == <<1::32>>
    assert String.reverse(number_of_frames) == <<0::32>>

    <<size_of_frame::binary-size(4), timestamp::binary-size(8)>> = frame_header
    assert String.reverse(size_of_frame) == <<byte_size(@vp9_frame)::32>>
    assert String.reverse(timestamp) == <<0::64>>

    {{:ok, buffer: {:output, ivf_buffer}, redemand: :output}, ivf_element_state} =
      IVF.VP9.handle_process(:input, vp9_buffer_2, nil, ivf_element_state)

    <<frame_header::binary-size(12), vp9_frame::binary()>> = ivf_buffer.payload
    <<size_of_frame::binary-size(4), timestamp::binary-size(8)>> = frame_header

    assert String.reverse(size_of_frame) == <<byte_size(@vp9_frame)::32>>

    # timestamp equal to 1 is expected because buffer timestamp is 10^8/3
    # and ivf timebase is 1/30:
    # x * 1/30 [s] = 10^8/3 * 10^(-9) [s] //*30/s
    # x = 30 * 1/30 * [s/s] = 1
    assert String.reverse(timestamp) == <<1::64>>
  end
end
