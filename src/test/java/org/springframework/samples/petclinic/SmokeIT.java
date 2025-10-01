package org.springframework.samples.petclinic;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SmokeIT {

  @Autowired
  private TestRestTemplate http;

  @Test
  void healthEndpointIsUp() {
    ResponseEntity<String> res = http.getForEntity("/actuator/health", String.class);
    assertThat(res.getStatusCode().is2xxSuccessful()).isTrue();
    assertThat(res.getBody()).contains("UP");
  }

  @Test
  void homePageLoads() {
    ResponseEntity<String> res = http.getForEntity("/", String.class);
    assertThat(res.getStatusCode().is2xxSuccessful()).isTrue();
    assertThat(res.getBody()).contains("Welcome"); // simple content check
  }
}
