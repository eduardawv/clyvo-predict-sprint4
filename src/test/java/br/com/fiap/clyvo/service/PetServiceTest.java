package br.com.fiap.clyvo.service;

import br.com.fiap.clyvo.dto.PetRequestDTO;
import br.com.fiap.clyvo.dto.PetResponseDTO;
import br.com.fiap.clyvo.exception.AcessoNegadoException;
import br.com.fiap.clyvo.exception.RecursoNaoEncontradoException;
import br.com.fiap.clyvo.model.Pet;
import br.com.fiap.clyvo.model.Tutor;
import br.com.fiap.clyvo.repository.PetRepository;
import br.com.fiap.clyvo.repository.TutorRepository;
import br.com.fiap.clyvo.security.AuthUser;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@DisplayName("PetService - cadastro e controle de acesso")
class PetServiceTest {

    private PetRepository petRepository;
    private TutorRepository tutorRepository;
    private AuthUser authUser;
    private PetService service;

    @BeforeEach
    void setUp() {
        petRepository = mock(PetRepository.class);
        tutorRepository = mock(TutorRepository.class);
        authUser = mock(AuthUser.class);
        service = new PetService(petRepository, tutorRepository, authUser);
    }

    private Tutor tutor(Long id) {
        return new Tutor(id, "Ana Beatriz Souza", "ana.souza@clyvo.com.br", "(11) 98765-4321", "hash");
    }

    private Pet pet(Long id, Tutor dono) {
        Pet pet = new Pet();
        pet.setId(id);
        pet.setNome("Thor");
        pet.setEspecie("Cachorro");
        pet.setRaca("Golden Retriever");
        pet.setIdade(4);
        pet.setPeso(32.5);
        pet.setHealthScore(100);
        pet.setTutor(dono);
        return pet;
    }

    @Test
    @DisplayName("Tutor cadastra pet: o dono vem do token e o health score comeca em 100")
    void tutorCadastraPetComoDono() {
        when(authUser.isTutor()).thenReturn(true);
        when(authUser.getId()).thenReturn(1L);
        when(tutorRepository.findById(1L)).thenReturn(Optional.of(tutor(1L)));
        when(petRepository.save(any(Pet.class))).thenAnswer(invocacao -> {
            Pet salvo = invocacao.getArgument(0);
            salvo.setId(10L);
            return salvo;
        });

        // O tutorId 99 enviado no JSON e ignorado quando quem cadastra e um TUTOR
        PetRequestDTO dto = new PetRequestDTO("Thor", "Cachorro", "Golden Retriever", 4, 32.5, 99L);
        PetResponseDTO resposta = service.cadastrar(dto);

        assertEquals(10L, resposta.id().longValue());
        assertEquals(1L, resposta.tutorId().longValue());
        assertEquals(100, resposta.healthScore().intValue());
        assertEquals("Thor", resposta.nome());
        verify(tutorRepository).findById(1L);
        verify(tutorRepository, never()).findById(99L);
    }

    @Test
    @DisplayName("Veterinario precisa informar o tutorId do pet")
    void veterinarioSemTutorId() {
        when(authUser.isTutor()).thenReturn(false);
        PetRequestDTO dto = new PetRequestDTO("Mel", "Cachorro", "Shih Tzu", 6, 7.8, null);

        assertThrows(IllegalArgumentException.class, () -> service.cadastrar(dto));
        verify(petRepository, never()).save(any(Pet.class));
    }

    @Test
    @DisplayName("Tutor nao acessa pet de outro tutor")
    void tutorNaoAcessaPetDeOutroTutor() {
        when(petRepository.findById(5L)).thenReturn(Optional.of(pet(5L, tutor(2L))));
        when(authUser.isTutor()).thenReturn(true);
        when(authUser.getId()).thenReturn(1L);

        assertThrows(AcessoNegadoException.class, () -> service.buscarPorId(5L));
    }

    @Test
    @DisplayName("Pet inexistente gera recurso nao encontrado")
    void petInexistente() {
        when(petRepository.findById(404L)).thenReturn(Optional.empty());

        assertThrows(RecursoNaoEncontradoException.class, () -> service.buscarPorId(404L));
    }

    @Test
    @DisplayName("Dono do pet consegue consulta-lo")
    void donoConsultaPet() {
        when(petRepository.findById(5L)).thenReturn(Optional.of(pet(5L, tutor(1L))));
        when(authUser.isTutor()).thenReturn(true);
        when(authUser.getId()).thenReturn(1L);

        PetResponseDTO resposta = service.buscarPorId(5L);

        assertEquals("Thor", resposta.nome());
        assertEquals(1L, resposta.tutorId().longValue());
    }
}
