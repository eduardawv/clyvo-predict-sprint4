package br.com.fiap.clyvo.service;

import br.com.fiap.clyvo.dto.TutorAuthResponseDTO;
import br.com.fiap.clyvo.dto.TutorLoginRequestDTO;
import br.com.fiap.clyvo.dto.TutorRequestDTO;
import br.com.fiap.clyvo.dto.TutorResponseDTO;
import br.com.fiap.clyvo.exception.AcessoNegadoException;
import br.com.fiap.clyvo.model.Tutor;
import br.com.fiap.clyvo.model.enums.Perfil;
import br.com.fiap.clyvo.repository.TutorRepository;
import br.com.fiap.clyvo.security.AuthUser;
import br.com.fiap.clyvo.security.CustomUserDetails;
import br.com.fiap.clyvo.security.JwtService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@DisplayName("TutorService - cadastro, login e permissoes")
class TutorServiceTest {

    private static final String EMAIL = "ana.souza@clyvo.com.br";
    private static final String SENHA = "Ana@Clyvo2026";
    private static final String HASH = "$2a$10$hashDeTeste";

    private TutorRepository repository;
    private JwtService jwtService;
    private PasswordEncoder passwordEncoder;
    private AuthUser authUser;
    private TutorService service;

    @BeforeEach
    void setUp() {
        repository = mock(TutorRepository.class);
        jwtService = mock(JwtService.class);
        passwordEncoder = mock(PasswordEncoder.class);
        authUser = mock(AuthUser.class);
        service = new TutorService(repository, jwtService, passwordEncoder, authUser);
    }

    private TutorRequestDTO requisicao() {
        return new TutorRequestDTO("Ana Beatriz Souza", EMAIL, "(11) 98765-4321", SENHA);
    }

    @Test
    @DisplayName("Cadastro grava a senha criptografada e o perfil TUTOR")
    void cadastroGravaSenhaCriptografada() {
        when(repository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(passwordEncoder.encode(SENHA)).thenReturn(HASH);
        when(repository.save(any(Tutor.class))).thenAnswer(invocacao -> {
            Tutor salvo = invocacao.getArgument(0);
            salvo.setId(1L);
            return salvo;
        });

        TutorResponseDTO resposta = service.cadastrar(requisicao());

        ArgumentCaptor<Tutor> captor = ArgumentCaptor.forClass(Tutor.class);
        verify(repository).save(captor.capture());
        assertEquals(HASH, captor.getValue().getSenha());
        assertEquals(Perfil.TUTOR, captor.getValue().getPerfil());
        assertEquals(1L, resposta.id().longValue());
        assertEquals(EMAIL, resposta.email());
    }

    @Test
    @DisplayName("Cadastro com e-mail repetido e recusado")
    void cadastroComEmailRepetido() {
        when(repository.findByEmail(EMAIL)).thenReturn(Optional.of(new Tutor()));

        RuntimeException erro = assertThrows(RuntimeException.class, () -> service.cadastrar(requisicao()));

        assertTrue(erro.getMessage().contains("cadastrado"));
        verify(repository, never()).save(any(Tutor.class));
    }

    @Test
    @DisplayName("Login com senha errada e recusado e nao gera token")
    void loginComSenhaErrada() {
        Tutor tutor = new Tutor(1L, "Ana Beatriz Souza", EMAIL, "(11) 98765-4321", HASH);
        when(repository.findByEmail(EMAIL)).thenReturn(Optional.of(tutor));
        when(passwordEncoder.matches("senha-errada", HASH)).thenReturn(false);

        assertThrows(RuntimeException.class,
                () -> service.autenticar(new TutorLoginRequestDTO(EMAIL, "senha-errada")));
        verify(jwtService, never()).gerarToken(any(CustomUserDetails.class));
    }

    @Test
    @DisplayName("Login correto devolve o token JWT com perfil TUTOR")
    void loginCorretoGeraToken() {
        Tutor tutor = new Tutor(1L, "Ana Beatriz Souza", EMAIL, "(11) 98765-4321", HASH);
        when(repository.findByEmail(EMAIL)).thenReturn(Optional.of(tutor));
        when(passwordEncoder.matches(SENHA, HASH)).thenReturn(true);
        when(jwtService.gerarToken(any(CustomUserDetails.class))).thenReturn("token-de-teste");

        TutorAuthResponseDTO resposta = service.autenticar(new TutorLoginRequestDTO(EMAIL, SENHA));

        assertEquals("token-de-teste", resposta.token());
        assertEquals("TUTOR", resposta.perfil());
        assertEquals(1L, resposta.id().longValue());
    }

    @Test
    @DisplayName("Tutor nao pode alterar a conta de outro tutor")
    void tutorNaoAlteraOutraConta() {
        when(authUser.isTutor()).thenReturn(true);
        when(authUser.getId()).thenReturn(1L);

        assertThrows(AcessoNegadoException.class, () -> service.atualizar(2L, requisicao()));
        verify(repository, never()).save(any(Tutor.class));
    }
}
