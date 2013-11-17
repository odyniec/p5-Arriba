requires "Data::Dump" => "0";
requires "HTTP::Date" => "0";
requires "HTTP::Parser::XS" => "0";
requires "HTTP::Status" => "0";
requires "IO::Socket" => "0";
requires "IO::Socket::SSL" => "0";
requires "Net::SPDY::Session" => "0";
requires "Net::Server::PreFork" => "0";
requires "Net::Server::SIG" => "0";
requires "Plack::Runner" => "0";
requires "Plack::TempBuffer" => "0";
requires "Plack::Util" => "0";
requires "Socket" => "0";
requires "base" => "0";
requires "constant" => "0";
requires "perl" => "5.008";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::Spec" => "0";
  requires "File::Spec::Functions" => "0";
  requires "File::Temp" => "0";
  requires "HTTP::Request::Common" => "0";
  requires "HTTP::Tiny::SPDY" => "0";
  requires "IO::Handle" => "0";
  requires "IPC::Open3" => "0";
  requires "List::Util" => "0";
  requires "Plack::LWPish" => "0";
  requires "Plack::Test::Suite" => "0";
  requires "Test::More" => "0";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "0";
  recommends "CPAN::Meta::Requirements" => "0";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "6.17";
};

on 'develop' => sub {
  requires "Pod::Coverage::TrustPod" => "0";
  requires "Test::CPAN::Changes" => "0.19";
  requires "Test::CPAN::Meta" => "0";
  requires "Test::Pod" => "1.41";
  requires "Test::Pod::Coverage" => "1.08";
};
