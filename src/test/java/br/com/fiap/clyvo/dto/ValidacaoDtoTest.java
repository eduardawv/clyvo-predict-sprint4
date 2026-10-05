package br.com.fiap.clyvo.dto;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import org.hibernate.validator.messageinterpolation.ParameterMessageInterpolator;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

@DisplayName("Validacao dos dados de entrada (Bean Validation)")
class ValidacaoDtoTest {

    private static ValidatorFactory factory;
    private static Validator validator;

    @BeforeAll
    static void criarValidador() {
        factory = Validation.byDefaultProvider()
                .configure()
                .messageInterpolator(new ParameterMessageInterpolator())
                .buildValidatorFactory();
        validator = factory.getValidator();
    }

    @AfterAll
    static void fecharValidador() {
        factory.close();
    }

    private static boolean temErroNoCampo(Set<? extends ConstraintViolation<?>> erros, String campo) {
        return erros.stream().anyMatch(erro -> erro.getPropertyPath().toString().equals(campo));
    }

    @Test
    @DisplayName("Tutor com todos os campos validos nao gera erros")
    void tutorValido() {
        TutorRequestDTO dto = new TutorRequestDTO("Ana Beatriz Souza", "ana.souza@clyvo.com.br",
                "(11) 98765-4321", "Ana@Clyvo2026");

        assertTrue(validator.validate(dto).isEmpty());
    }

    @Test
    @DisplayName("Tutor com e-mail invalido e rejeitado")
    void tutorComEmailInvalido() {
        TutorRequestDTO dto = new TutorRequestDTO("Ana Beatriz Souza", "email-invalido",
                "(11) 98765-4321", "Ana@Clyvo2026");

        Set<ConstraintViolation<TutorRequestDTO>> erros = validator.validate(dto);

        assertFalse(erros.isEmpty());
        assertTrue(temErroNoCampo(erros, "email"));
    }

    @Test
    @DisplayName("Pet com peso negativo e rejeitado")
    void petComPesoNegativo() {
        PetRequestDTO dto = new PetRequestDTO("Thor", "Cachorro", "Golden Retriever", 4, -1.0, null);

        Set<ConstraintViolation<PetRequestDTO>> erros = validator.validate(dto);

        assertFalse(erros.isEmpty());
        assertTrue(temErroNoCampo(erros, "peso"));
    }

    @Test
    @DisplayName("Pet sem nome e rejeitado")
    void petSemNome() {
        PetRequestDTO dto = new PetRequestDTO("", "Gato", "Persa", 2, 4.1, null);

        Set<ConstraintViolation<PetRequestDTO>> erros = validator.validate(dto);

        assertTrue(temErroNoCampo(erros, "nome"));
    }
}
