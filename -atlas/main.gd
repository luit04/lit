extends Node
	
func _ready() -> void:
	
	var rd = RenderingServer.get_rendering_device()
	
	var linear_clamp_sampler_state = RDSamplerState.new()
	linear_clamp_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_clamp_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_clamp_sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	
	var linear_clamp_sampler = rd.sampler_create(linear_clamp_sampler_state)
	
	var linear_repeat_sampler_state = RDSamplerState.new()
	linear_repeat_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_repeat_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_repeat_sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_repeat_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	linear_repeat_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	linear_repeat_sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	
	var linear_repeat_sampler = rd.sampler_create(linear_repeat_sampler_state)
	
	var lut_format = RDTextureFormat.new()
	lut_format.width = 512
	lut_format.height = 512
	lut_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	lut_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	
	# Transmittance LUT
	
	var transmittance_lut = rd.texture_create(lut_format, RDTextureView.new())
	
	var transmittance_lut_uniform_image = RDUniform.new()
	transmittance_lut_uniform_image.binding = 0
	transmittance_lut_uniform_image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	transmittance_lut_uniform_image.add_id(transmittance_lut)
	
	var transmittance_lut_uniform_sampler = RDUniform.new()
	transmittance_lut_uniform_sampler.binding = 0
	transmittance_lut_uniform_sampler.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	transmittance_lut_uniform_sampler.add_id(linear_clamp_sampler)
	transmittance_lut_uniform_sampler.add_id(transmittance_lut)
	
	# Multiple Scattering LUT
	
	var multiple_scattering_lut = rd.texture_create(lut_format, RDTextureView.new())
	
	var multiple_scattering_lut_uniform_image = RDUniform.new()
	multiple_scattering_lut_uniform_image.binding = 1
	multiple_scattering_lut_uniform_image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	multiple_scattering_lut_uniform_image.add_id(multiple_scattering_lut)
	
	var multiple_scattering_lut_uniform_sampler = RDUniform.new()
	multiple_scattering_lut_uniform_sampler.binding = 1
	multiple_scattering_lut_uniform_sampler.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	multiple_scattering_lut_uniform_sampler.add_id(linear_clamp_sampler)
	multiple_scattering_lut_uniform_sampler.add_id(multiple_scattering_lut)
	
	# Noise Texture
	
	var noise_format = RDTextureFormat.new()
	noise_format.width = 1024
	noise_format.height = 1024
	noise_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	noise_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	
	var noise_texture = rd.texture_create(noise_format, RDTextureView.new())
	
	var noise_uniform_image = RDUniform.new()
	noise_uniform_image.binding = 0
	noise_uniform_image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	noise_uniform_image.add_id(noise_texture)
	
	var noise_uniform_sampler = RDUniform.new()
	noise_uniform_sampler.binding = 2
	noise_uniform_sampler.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	noise_uniform_sampler.add_id(linear_repeat_sampler)
	noise_uniform_sampler.add_id(noise_texture)
	
	# Starmap
	
	var starmap_image_texture = RenderingServer.texture_2d_create(Image.load_from_file("res://starmap_2020_4k.exr"))
	var starmap_texture = RenderingServer.texture_get_rd_texture(starmap_image_texture)
	
	var starmap_uniform_sampler = RDUniform.new()
	starmap_uniform_sampler.binding = 3
	starmap_uniform_sampler.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	starmap_uniform_sampler.add_id(linear_repeat_sampler)
	starmap_uniform_sampler.add_id(starmap_texture)
	
	# Final Sky
	
	var atlas_format = RDTextureFormat.new()
	atlas_format.width = 4096
	atlas_format.height = 4096
	atlas_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	atlas_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var atlas_texture = rd.texture_create(atlas_format, RDTextureView.new())
	
	var atlas_uniform_image = RDUniform.new()
	atlas_uniform_image.binding = 4
	atlas_uniform_image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	atlas_uniform_image.add_id(atlas_texture)
	
	# Rendering
	
	var list = 0
	var uniforms = []
	var uniform_set = RID()
	
	# Transmittance LUT Rendering
	
	uniforms = [transmittance_lut_uniform_image]
	
	var transmittance_shader = rd.shader_create_from_spirv(load("res://shaders/transmittance.glsl").get_spirv())
	var transmittance_pipeline = rd.compute_pipeline_create(transmittance_shader)
	
	uniform_set = rd.uniform_set_create(uniforms, transmittance_shader, 0)
	
	list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, transmittance_pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_dispatch(list, 256, 256, 1)
	rd.compute_list_end()
	
	rd.free_rid(uniform_set)
	
	# Multiple Scattering LUT Rendering
	
	uniforms = [transmittance_lut_uniform_sampler, multiple_scattering_lut_uniform_image]
	
	var multiple_scattering_shader = rd.shader_create_from_spirv(load("res://shaders/multiple_scattering.glsl").get_spirv())
	var multiple_scattering_pipeline = rd.compute_pipeline_create(multiple_scattering_shader)
	
	uniform_set = rd.uniform_set_create(uniforms, multiple_scattering_shader, 0)
	
	list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, multiple_scattering_pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_dispatch(list, 256, 256, 1)
	rd.compute_list_end()
	
	rd.free_rid(uniform_set)
	
	# Compute 2D Noise
	
	uniforms = [noise_uniform_image]
	
	var noise_shader = rd.shader_create_from_spirv(load("res://shaders/noise.glsl").get_spirv())
	var noise_pipeline = rd.compute_pipeline_create(noise_shader)
	
	uniform_set = rd.uniform_set_create(uniforms, noise_shader, 0)
	
	list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, noise_pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_dispatch(list, 512, 512, 1)
	rd.compute_list_end()
	
	rd.free_rid(uniform_set)
	
	# Sky Rendering
	
	uniforms = [
		transmittance_lut_uniform_sampler, 
		multiple_scattering_lut_uniform_sampler, 
		noise_uniform_sampler, 
		starmap_uniform_sampler, 
		atlas_uniform_image
	]
	
	var atlas_shader = rd.shader_create_from_spirv(load("res://shaders/atlas.glsl").get_spirv())
	var atlas_pipeline = rd.compute_pipeline_create(atlas_shader)
	
	uniform_set = rd.uniform_set_create(uniforms, atlas_shader, 0)
	
	list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, atlas_pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_dispatch(list, 1024, 1024, 1)
	rd.compute_list_end()
	
	rd.free_rid(uniform_set)
	
	var output_image = Image.create_from_data(atlas_format.width, atlas_format.height, false, Image.FORMAT_RGBA8, rd.texture_get_data(atlas_texture, 0))
	output_image.save_png("res://cubemap_0.png")
	
	# Free Resource Memory
	
	rd.free_rid(transmittance_pipeline)
	rd.free_rid(transmittance_shader)
	
	rd.free_rid(multiple_scattering_pipeline)
	rd.free_rid(multiple_scattering_shader)
	
	rd.free_rid(noise_pipeline)
	rd.free_rid(noise_shader)
	
	rd.free_rid(atlas_pipeline)
	rd.free_rid(atlas_shader)
	
	rd.free_rid(linear_clamp_sampler)
	rd.free_rid(linear_repeat_sampler)
	
	rd.free_rid(transmittance_lut)
	rd.free_rid(multiple_scattering_lut)
	rd.free_rid(starmap_texture)
	rd.free_rid(atlas_texture)
	
	rd.free_rid(noise_texture)
