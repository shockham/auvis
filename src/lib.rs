use std::collections::HashMap;

use infuse::{request_animation_frame, RenderItem, Renderer, Uniform};
use instant;
use wasm_bindgen::prelude::*;
use wasm_bindgen::JsCast;
use web_sys::{AudioContext, OscillatorType, BiquadFilterType, console};

const VERT: &str = include_str!("./shaders/vert.glsl");
const FRAG: &str = include_str!("./shaders/frag.glsl");

#[wasm_bindgen(start)]
pub async fn start() -> Result<(), JsValue> {
    let mut renderer = Renderer::new()?;

    let start_time = instant::now();

    // add a shader that will use the uniform
    renderer.add_shader("colour".into(), VERT.into(), FRAG.into())?;

    // create the uniforms for the render item
    let mut uniforms = HashMap::new();
    uniforms.insert("time".to_string(), Uniform::Float(start_time as f32));


    // web audio init
    let ctx = web_sys::AudioContext::new()?;
    // Create our web audio objects.
    let primary = ctx.create_oscillator()?;
    let fm_osc = ctx.create_oscillator()?;
    let gain = ctx.create_gain()?;
    let fm_gain = ctx.create_gain()?;
    let filter = ctx.create_biquad_filter()?;
    let dist = ctx.create_wave_shaper()?;
    let comp = ctx.create_dynamics_compressor()?;

    let spectrum = ctx.create_analyser()?;

    // Some initial settings:
    primary.set_type(OscillatorType::Sine);
    primary.frequency().set_value(440.0); // A4 note
    gain.gain().set_value(0.3); // starts muted
    fm_gain.gain().set_value(1.0); // no initial frequency modulation
    fm_osc.set_type(OscillatorType::Sine);
    fm_osc.frequency().set_value(220.0);
    filter.set_type(BiquadFilterType::Lowpass);
    spectrum.set_fft_size(1024);

    comp.threshold().set_value(-50f32);
    comp.ratio().set_value(5f32);

    // Connect the nodes up!
    primary.connect_with_audio_node(&gain)?;
    //filter.connect_with_audio_node(&dist)?;
    //dist.connect_with_audio_node(&gain)?;
    gain.connect_with_audio_node(&comp)?;
    comp.connect_with_audio_node(&spectrum)?;
    spectrum.connect_with_audio_node(&ctx.destination())?;


    fm_osc.connect_with_audio_node(&fm_gain)?;
    //fm_gain.connect_with_audio_param(&primary.frequency())?;

    // Start the oscillators!
    primary.start()?;
    fm_osc.start()?;


    let render_item = RenderItem::new(
        vec![
            -1.0, -1.0, 0.0, 1.0, -1.0, 0.0, 1.0, 1.0, 0.0, -1.0, 1.0, 0.0, -1.0, -1.0, 0.0, 1.0,
            1.0, 0.0,
        ],
        "colour".into(),
        Some(uniforms),
    );

    let mut render_items = vec![render_item];

    request_animation_frame!({
        let tick_time = instant::now();
        render_items[0].set_uniform(
            "time".to_string(),
            Uniform::Float((tick_time / 500f64) as f32),
        );

        let mut freq_buf: [f32; 1024] = [0f32; 1024];
        //spectrum.get_float_frequency_data(&mut freq_buf);
        spectrum.get_float_time_domain_data(&mut freq_buf);

        let band_0:f32 = (&freq_buf[..128]).iter().sum();
        let band_1:f32 = (&freq_buf[128..256]).iter().sum();
        let band_2:f32 = (&freq_buf[256..384]).iter().sum();
        let band_3:f32 = (&freq_buf[384..512]).iter().sum();
        let band_4:f32 = (&freq_buf[512..640]).iter().sum();
        let band_5:f32 = (&freq_buf[640..768]).iter().sum();
        let band_6:f32 = (&freq_buf[768..896]).iter().sum();
        let band_7:f32 = (&freq_buf[896..]).iter().sum();

        render_items[0].set_uniform(
            "freq_1".to_string(),
            Uniform::Vec4(
                band_0 / 128f32,
                band_1 / 128f32,
                band_2 / 128f32,
                band_3 / 128f32
            ),
        );

        render_items[0].set_uniform(
            "freq_2".to_string(),
            Uniform::Vec4(
                band_4 / 128f32,
                band_5 / 128f32,
                band_6 / 128f32,
                band_7 / 128f32
            ),
        );

        primary.frequency().set_value(
            220.0 + ((tick_time as f32 / 500f32).sin() * 10f32).ceil() * 50f32
        );
        fm_osc.frequency().set_value(1.0 + ((tick_time as f32 / 50f32).cos()));

        renderer.draw(&render_items).unwrap();
    });

    Ok(())
}
