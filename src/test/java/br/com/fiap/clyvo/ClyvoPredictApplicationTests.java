package br.com.fiap.clyvo;

import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
@Disabled("Sobe o contexto completo e exige banco de dados e chaves JWT; no CI rodam os testes unitarios. A integracao com o Azure SQL e verificada no CD (teste de fumaca).")
class ClyvoPredictApplicationTests {

	@Test
	void contextLoads() {
	}

}
