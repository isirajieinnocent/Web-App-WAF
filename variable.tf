Variable "WebAPP" {
    description = "Name of lb"
    type = string
    default = "WebAPP"
}

varaible "ws_wafv2_ip_set"{
  description = " The name of WAF IP set"
  type = string
  default = Wafv2IPSet
}


varaible ""aws_security_group"{
    description = "The name of LB security group"
    type = string
    default = lb_sg
}