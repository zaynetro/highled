# Highled - Higher level ledger

Helps manage ledger file with ease.

[Ledger](http://www.ledger-cli.org/) needs to be installed beforehand.


## Download

* `curl https://raw.githubusercontent.com/zaynetro/highled/master/highled.sh > highled.sh && chmod 755 highled.sh`


## Usage

```
Highled - higher level ledger

Usage:
  highled init                 Configure highled (will be run once before any other command)
  highled flush                Remove all files created by highled
  highled pay <options>        Make a payment transaction (see detailed description below)
  highled last                 Print last transaction
  highled undo                 Remove last transaction
  highled withdraw <options>   Withdraw money from bank card (see below)
  highled set-alias <k> <v>    Set alias value <v> for the key <k>
  highled rm-alias <k>         Remove alias for the key <k>
  highled show-alias <k>       Print alias value for the key <k>, if <k> omitted print all
  highled exec <options>       Execute ledger with highled balance file and <options>
  highled print                Print dataset and config file locations
  highled {version|-v|-V}      Print highled version

Payment:
 highled pay [flags] [<amount> for <expense>] with <what> [<date>] [-d <description>]
 Flags:
   -y             Auto-confirm transaction
   --no-alias     Don't try to resolve aliases
   -nas           Shorthand for --no-alias

Withdrawal:
 highled withdraw [flags] <amount> from <where> [<date>] [-d <description>]
 Flags: (the same as for payment)

Examples:
  $ highled pay 11.50 for Lunch with visa
  2015/06/20  Lunch purchase with Visa
    Expenses:Lunch      11.50 EUR
    Liabilities:Visa

  $ highled pay 34 for Food with cash yesterday -d "Chinatown dinner"
  2015/06/19  Food:Fastfood purchase with Cash
    Expenses:Food:Fastfood      34 EUR
    Assets:Cash
```


## Aliases

`Highled` will try to find mathing alias value for every user input. When your input matches an alias it will be changed to the value you defined when configuring alias.

## Currency

### Default

`Highled` will try to use default currency for every input which lacks currency. You can specify default currency by setting `DEFAULT_CURRENCY` alias to the value you need (`highled set-alias DEFAULT_CURRENCY GBP`). Or manually by modifying configuration file (use `highled print` to see file location).

### Specify

The other way is to specify currency every time you input a value (eg: `highled pay 10.10EUR for Food with cash`).

**NOTE:** Currently script understands currency which follows the payment amount, not those that stand before such as dollar sign ($10.10 doesn't work).


## Basic reporting

TO BE DONE

## TO DO

* More clever payment command
  * <s>Understand multiple expenses within one transaction</s>
  * Provide `--no-alias` flag
  * <s>Transaction confirmation</s>
* Income command
  * Calls payment method
* Withdraw command
  * **Just call payment method** with specific arguments
  * <s>Basic functionality</s>
  * Flag support
  * Date support
  * Description support
* Automatically transfer to new balance sheet each year
* Basic reporting
  * Provide examples of ledger reporting?
* Simple visualisation for expense categories
  * Host simple web-server and host graphs?
  * Electron application?
  * Use d3.js or similar lib

## License

License - MIT
