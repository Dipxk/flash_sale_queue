require "rails_helper"

RSpec.describe AdmissionControl do
  it "atomically respects max concurrent slots" do
    sale = create(:flash_sale, max_concurrent_checkouts: 2)
    control = described_class.new(sale)
    control.reset!

    acquired = 20.times.map do
      Thread.new { control.try_acquire! }
    end.map(&:value)

    expect(acquired.count(true)).to eq(2)
    expect(control.active_count).to eq(2)
  end
end
