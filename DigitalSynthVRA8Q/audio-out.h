// refs http://playground.arduino.cc/Code/PCMAudio

#pragma once

#include "common.h"

template <uint8_t T>
class AudioOut {
  static uint8_t m_count;
  static uint8_t m_busy;
  static uint8_t m_busyContinuousCont;

public:
  INLINE static void open() {
    pinMode(L_MONO_AUDIO_OUT_PIN, OUTPUT);
    pinMode(R_AUDIO_OUT_PIN,      OUTPUT);
    pinMode(CPU_BUSY_LED_OUT_PIN, OUTPUT);

    // Timer/Counter0 (8-bit Fast PWM, Inverting, 62500 Hz)
#if (L_MONO_AUDIO_OUT_PIN == 6)
    OCR0A  = 0x7F;
    TCCR0A = 0xC3;
#else
    OCR0B  = 0x7F;
    TCCR0A = 0x33;
#endif

    // Timer/Counter2 (8-bit Fast PWM, Inverting, 62500 Hz)
    OCR2A  = 0x7F;
    TCCR2A = 0xC3;

    // Timer/Counter1 (9-bit Fast PWM, 31250 Hz)
    TCCR1A = 0x02;

    // Start 0 -> 2 -> 1
    TCCR0B = 0x01;
    TCCR2B = 0x01;
    TCCR1B = 0x09;

    m_count = 0;
    m_busy = 0;
    m_busyContinuousCont = 0;
  }

  INLINE static void write(int8_t level) {
    uint8_t leftMono = 0x7F - level;
    uint8_t right    = 0x7F - level;

#if defined(DEBUG)
    // Output Elapsed Time as Channel Pressure (of Channel 16)
    ++m_count;
    if (m_count == 0x7F) {
      UDR0 = 0xDF;
    } else if (m_count == 0xFF) {
      uint8_t tcnt = TCNT1 >> 2;
      UDR0 = tcnt;
      m_count = 0;
    }
#endif

    if (TIFR1 & _BV(TOV1)) {
      // CPU BUSY
      if (m_busy) {
        ++m_busyContinuousCont;
      }
      m_busy = 1;
    } else {
      m_busy = 0;
      m_busyContinuousCont = 0;
      while ((TIFR1 & _BV(TOV1)) == 0);
    }
    TIFR1 = _BV(TOV1);

#if (L_MONO_AUDIO_OUT_PIN == 6)
    OCR0A = leftMono;
    OCR2A = right;
#else
    OCR0B = leftMono;
    OCR2A = right;
#endif

    if (m_busyContinuousCont >= 4) {
      PORTB = _BV(5);    // Turn on CPU Busy LED
    } else {
      PORTB = 0x00;      // Turn off CPU Busy LED
    }

  }
};

template <uint8_t T> uint8_t AudioOut<T>::m_count;
template <uint8_t T> uint8_t AudioOut<T>::m_busy;
template <uint8_t T> uint8_t AudioOut<T>::m_busyContinuousCont;
