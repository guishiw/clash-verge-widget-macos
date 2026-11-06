import Testing
@testable import ClashVergeWidgetCore

@Suite("Traffic rate sampling")
struct RateSamplerTests {
    @Test("Computes rates and handles counter resets")
    func computesRates() {
        var sampler = RateSampler()
        let first = sampler.sample(uploadTotal: 1_000, downloadTotal: 5_000, connections: 2, at: 10)
        #expect(first.upload == 0)
        #expect(first.download == 0)

        let second = sampler.sample(uploadTotal: 3_000, downloadTotal: 11_000, connections: 3, at: 12)
        #expect(second.upload == 1_000)
        #expect(second.download == 3_000)
        #expect(second.connections == 3)

        let reset = sampler.sample(uploadTotal: 100, downloadTotal: 50, connections: 0, at: 13)
        #expect(reset.upload == 0)
        #expect(reset.download == 0)
    }
}
