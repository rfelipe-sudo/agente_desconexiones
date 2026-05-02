package com.karimpichara.turingandroid

/**
 * Normaliza un RUT al formato con guion: "16405856-5".
 *
 * Acepta dos formatos de entrada:
 *  - Sin guion: "164058565"  → "16405856-5"   (comportamiento original de turing)
 *  - Con guion: "16405856-5" → "16405856-5"   (formato que usa creabox)
 */
fun formatRut(rut: String): String {
    if (rut.length < 2) return rut
    if (rut.contains('-')) return rut          // ya está formateado
    return rut.dropLast(1) + "-" + rut.last()
}
