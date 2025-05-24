@tool
extends Node

signal texture_ready(texture)
signal generation_progress(normalized_progress)

const MAX_FREQUENCY: float = 3000.0 # Maximum frequency captured
const IMAGE_HEIGHT: int = 64

var image_compression: float = 10.0 # How many samples in one pixel
var background_color = Color(0, 0, 0, 0)
var foreground_color = Color.SILVER




# =============================================================================


const SAMPLING_RATE = 2.0*MAX_FREQUENCY
const IMAGE_HEIGHT_FACTOR: float = float(IMAGE_HEIGHT) / 256.0 # Converts sample raw height to pixel
const IMAGE_CENTER_Y = int(round(IMAGE_HEIGHT / 2.0))

var is_working := false
var must_abort := false


func generate_preview(stream: AudioStreamWAV, image_max_width: int = 500):
	if not stream:
		return
	
	if stream.format == AudioStreamWAV.FORMAT_IMA_ADPCM:
		return
	
	if image_max_width <= 0:
		return
	
	if is_working:
		must_abort = true
		while is_working:
			await get_tree().process_frame
	
	is_working = true
	
	var data = stream.data
	var data_size = data.size()
	var is_16bit = (stream.format == AudioStreamWAV.FORMAT_16_BITS)
	var is_stereo = stream.stereo
	
	var sample_interval = 1
	if stream.mix_rate > SAMPLING_RATE:
		sample_interval = int(round(stream.mix_rate / SAMPLING_RATE))
	if is_16bit:
		sample_interval *= 2
	if is_stereo:
		sample_interval *= 2
	
	var reduced_data = PackedByteArray()
	var reduced_data_size = int(floor(data_size / float(sample_interval)))
	reduced_data.resize(reduced_data_size)
	
	var sample_in_i := 1 if is_16bit else 0
	var sample_out_i := 0
	while (sample_in_i < data_size) and (sample_out_i < reduced_data_size):
		reduced_data[sample_out_i] = data[sample_in_i]
		sample_in_i += sample_interval
		sample_out_i += 1
		
		if must_abort:
			is_working = false
			must_abort = false
			return
	
	image_compression = ceil(reduced_data_size / float(image_max_width))
	var img_width = floor(reduced_data_size / image_compression)
	var img = Image.create(img_width, IMAGE_HEIGHT, true, Image.FORMAT_RGBA8)
	img.fill(background_color)
	
	var sample_i = 0
	var img_x = 0
	var final_sample_i = reduced_data_size - image_compression
	
	while sample_i < final_sample_i:
		var min_val_left := 128
		var max_val_left := 128
		var min_val_right := 128
		var max_val_right := 128
		
		for block_i in range(image_compression):
			if sample_i >= reduced_data_size:
				break
			var sample_val = reduced_data[sample_i] + 128
			if sample_val >= 256:
				sample_val -= 256

			if is_stereo:
				if (sample_i % 2) == 0:
					if sample_val < min_val_left:
						min_val_left = sample_val
					if sample_val > max_val_left:
						max_val_left = sample_val
				else:
					if sample_val < min_val_right:
						min_val_right = sample_val
					if sample_val > max_val_right:
						max_val_right = sample_val
			else:
				if sample_val < min_val_left:
					min_val_left = sample_val
				if sample_val > max_val_left:
					max_val_left = sample_val

			sample_i += 1

			if is_stereo:
				# Draw top (left)
				_draw_half_waveform(img, img_x, min_val_left, max_val_left, 0, IMAGE_HEIGHT / 2)
				# Draw bottom (right)
				_draw_half_waveform(img, img_x, min_val_right, max_val_right, IMAGE_HEIGHT / 2, IMAGE_HEIGHT / 2)
			else:
				# Mono: use full height
				_draw_half_waveform(img, img_x, min_val_left, max_val_left, 0, IMAGE_HEIGHT)

		img_x += 1

		if must_abort:
			is_working = false
			must_abort = false
			return

		if (sample_i % 100) == 0:
			var progress = sample_i / final_sample_i
			emit_signal("generation_progress", progress)
			await get_tree().process_frame

	is_working = false
	emit_signal("texture_ready", ImageTexture.create_from_image(img))
	
func _draw_half_waveform(img: Image, x: int, min_val: int, max_val: int, y_offset: int, draw_height: int):
	var scale = draw_height / 256.0
	var center_y = y_offset + int(draw_height / 2)

	var min_y = int(center_y - (max_val - 128) * scale)
	var max_y = int(center_y - (min_val - 128) * scale)

	min_y = clamp(min_y, y_offset, y_offset + draw_height - 1)
	max_y = clamp(max_y, y_offset, y_offset + draw_height - 1)

	for y in range(min_y, max_y + 1):
		img.set_pixel(x, y, foreground_color)
		
func _reset_to_blank():
	var img = Image.create(1, IMAGE_HEIGHT, true, Image.FORMAT_RGBA8)
	img.fill(Color.DARK_SLATE_GRAY)
	emit_signal("texture_ready", ImageTexture.create_from_image(img))
	
