require_relative 'constants'

$file = File.open("osc-table.h", "w")

$file.printf("#pragma once\n\n")

def freq_from_note_number(note_number, pr = false)
  cent = (note_number * 100.0) - 6900.0
  hz = A4_PITCH * (2.0 ** (cent / 1200.0))
  bit = (SAMPLING_RATE.to_f / (1 << OSC_PHASE_RESOLUTION_BITS)) * ((0x100.to_f - 0xF0) / 0xFF)
  hz -= bit  # Correct bit = (m_rnd >= 0xF0) in "osc.h"
  if note_number < NOTE_NUMBER_MIN + 12
    freq = (hz * (1 << OSC_PHASE_RESOLUTION_BITS) / SAMPLING_RATE).round.to_i
  else
    freq = (hz * (1 << OSC_PHASE_RESOLUTION_BITS) / SAMPLING_RATE).floor.to_i
    freq = freq + 1 if freq.even?
  end
  if pr
    printf("%3d, %+f, %d\n",note_number, 1.0 - freq.to_f * SAMPLING_RATE / (hz * (1 << OSC_PHASE_RESOLUTION_BITS)), freq)
  end
  return freq
end

$file.printf("const uint16_t g_osc_freq_table[] = {\n  ")
(NOTE_NUMBER_MIN..NOTE_NUMBER_MAX).each do |note_number|
  freq = freq_from_note_number(note_number, true)

  $file.printf("0x%04X,", freq)
  if note_number == DATA_BYTE_MAX
    $file.printf("\n")
  elsif note_number % 12 == (12 - 1)
    $file.printf("\n  ")
  else
    $file.printf(" ")
  end
end
$file.printf("};\n\n")

$file.printf("const int8_t g_osc_tune_table[] = {\n  ")
(0..(1 << OSC_TUNE_TABLE_STEPS_BITS) - 1).each do |i|
  tune_rate = ((2.0 ** ((i - (1 << (OSC_TUNE_TABLE_STEPS_BITS - 1))) / (12.0 * (1 << OSC_TUNE_TABLE_STEPS_BITS)))) *
               (1 << OSC_TUNE_DENOMINATOR_BITS) / 1.0).round -
              (1 << OSC_TUNE_DENOMINATOR_BITS) / 1.0

  $file.printf("%5d,", tune_rate)
  if i == (1 << OSC_TUNE_TABLE_STEPS_BITS) - 1
    $file.printf("\n")
  elsif i % 8 == 7
    $file.printf("\n  ")
  else
    $file.printf(" ")
  end
end
$file.printf("};\n\n")

def generate_osc_wave_table(name, last, amp, organ = false)
  $file.printf("const uint8_t g_osc_#{name}_wave_table_h%d[] PROGMEM = {\n  ", last)
  (0..(1 << OSC_WAVE_TABLE_SAMPLES_BITS)).each do |n|
    level = 0
    max = organ ? last * 2 : last
    (1..max).each do |k|
      level += yield(n, k)
    end
    level *= amp
    level = (level * OSC_WAVE_TABLE_AMPLITUDE).floor.to_i
    level += 0x100 if level < 0
    $file.printf("0x%02X,", level)
    if n == (1 << OSC_WAVE_TABLE_SAMPLES_BITS)
      $file.printf("\n")
    elsif n % 16 == 15
      $file.printf("\n  ")
    else
      $file.printf(" ")
    end
  end
  $file.printf("};\n\n")
end

$osc_harmonics_restriction_table = []

(NOTE_NUMBER_MIN..NOTE_NUMBER_MAX).each do |note_number|
  freq = freq_from_note_number(((note_number + (2 - 1)) / 2) * 2 + 1)
  $osc_harmonics_restriction_table << (freq + 1)
end

def last_harmonic(freq, organ = false, organ_last)
  last = (freq != 0) ? ((FREQUENCY_MAX * (1 << OSC_PHASE_RESOLUTION_BITS)) /
                        ((freq + OSC_DETUNE_FREQ_MAX) * SAMPLING_RATE)) : 0
  last = organ_last if organ && last > organ_last
  last = 12 if last == 13
  last = 10 if last == 11
  last = 8 if last == 9
  last = 6 if last == 7
  last = [last, 127].min
  last
end

def generate_osc_wave_table_arrays(organ = false, organ_last = 8)
  $osc_harmonics_restriction_table.
    map { |freq| last_harmonic(freq, organ, organ_last) }.uniq.sort.reverse.each do |i|
    yield(i)
  end
end

generate_osc_wave_table_arrays do |last|
  generate_osc_wave_table("saw", last, 1.0) do |n, k|
    (2.0 / Math::PI) * Math.sin((2.0 * Math::PI) *
                                (n.to_f / (1 << OSC_WAVE_TABLE_SAMPLES_BITS)) * k) / k
  end
end

generate_osc_wave_table_arrays do |last|
  generate_osc_wave_table("pulse", last, 1.0 / Math.sqrt(3)) do |n, k|
    if k % 2 == 1
      (4.0 / Math::PI) * Math.sin((2.0 * Math::PI) *
                                  (n.to_f / (1 << OSC_WAVE_TABLE_SAMPLES_BITS)) * k) / k
    else
      0.0
    end
  end
end

generate_osc_wave_table("sin", 1, ((8.0 * 127.0) / (6.0 * 128.0))) do |n, k|
  Math.sin((2.0 * Math::PI) * (n.to_f / (1 << OSC_WAVE_TABLE_SAMPLES_BITS)) * k)
end

def generate_osc_wave_tables_array(name, organ = false, organ_last = 8)
  $file.printf("const uint8_t* const g_osc_#{name}_wave_tables[] PROGMEM = {\n  ")
  $osc_harmonics_restriction_table.each_with_index do |freq, idx|
    $file.printf("g_osc_#{name}_wave_table_h%-3d,", last_harmonic(freq, organ, organ_last))
    if idx == DATA_BYTE_MAX
      $file.printf("\n")
    elsif (idx + 2) % 2 == (2 - 1)
      $file.printf("\n  ")
    else
      $file.printf(" ")
    end
  end
  $file.printf("};\n\n")
end

generate_osc_wave_tables_array("saw")
generate_osc_wave_tables_array("pulse")

$file.close
