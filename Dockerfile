FROM docker:1.11.2
ADD ./ddc_install.sh /ddc_install.sh
ENTRYPOINT ["sh", "/ddc_install.sh"]
