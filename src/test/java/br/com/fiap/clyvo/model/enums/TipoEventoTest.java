package br.com.fiap.clyvo.model.enums;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

@DisplayName("Health Score - regras do TipoEvento")
class TipoEventoTest {

    @Test
    @DisplayName("Vacina soma 10 pontos ao score")
    void vacinaSomaPontos() {
        assertEquals(80, TipoEvento.VACINA.calcularNovoScore(70));
    }

    @Test
    @DisplayName("Score nunca passa de 100")
    void scoreLimitadoA100() {
        assertEquals(100, TipoEvento.VACINA.calcularNovoScore(95));
    }

    @Test
    @DisplayName("Score nunca fica abaixo de 0")
    void scoreLimitadoA0() {
        assertEquals(0, TipoEvento.ACIDENTE.calcularNovoScore(30));
    }

    @Test
    @DisplayName("Doenca grave reduz 40 pontos")
    void doencaGraveReduzScore() {
        assertEquals(60, TipoEvento.DOENCA_GRAVE.calcularNovoScore(100));
    }

    @Test
    @DisplayName("Cada tipo de evento tem o impacto definido na regra de negocio")
    void impactosDefinidos() {
        assertEquals(5, TipoEvento.CONSULTA_ROTINA.getImpactoScore());
        assertEquals(-30, TipoEvento.CIRURGIA.getImpactoScore());
        assertEquals(-5, TipoEvento.RELATO_SINTOMA.getImpactoScore());
    }
}
