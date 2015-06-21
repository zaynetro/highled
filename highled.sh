#!/bin/bash

{

DB_DIR=./.highled
CONFIG_FILE=$DB_DIR/config
DB_DATAFILE=$DB_DIR/current.ldg

case $OSTYPE in
	"darwin"*)
		PLATFORM="darwin"
		;;

	"linux-gnu")
		PLATFORM="linux"
		;;
esac

print_usage() {
	read -r -d '' output << EOM

Highled - higher level ledger

Usage:
  highled init                 Configure highled (will be run once before any other command)
  highled flush                Remove all files created by highled
  highled pay <options>        Make a payment transaction (see detailed description below)
  highled last                 Print last transaction
  highled undo                 Remove last transaction
  highled set-alias <k> <v>    Set alias value <v> for the key <k>
  highled rm-alias <k>         Remove alias for the key <k>
  highled show-alias <k>       Print alias value for the key <k>, if <k> omitted print all
  highled exec <options>       Execute ledger with specified dataset file and <options>
  highled print                Print dataset and config file locations

Payment:
 highled pay <amount> for <expense> with <what> [<date>] [-d <description>]

Examples:
  $ highled pay 11.50 for Lunch with visa
  2015/06/20  Lunch purchase with Visa
    Expenses:Lunch	11.50 EUR
    Liabilities:Visa

  $ highled pay 34 for Food with cash yesterday -d "Chinatown dinner"
  2015/06/19  Food:Fastfood purchase with Cash
    Expenses:Food:Fastfood	34 EUR
    Assets:Cash

EOM

	echo "$output" | less
}

init_config() {
	if [[ -f $CONFIG_FILE ]]; then
		return
	fi

	touch $CONFIG_FILE

	echo "# Default aliases" >> $CONFIG_FILE
	echo "DEFAULT_CURRENCY=EUR" >> $CONFIG_FILE
	echo "VISA=Liabilities:Visa" >> $CONFIG_FILE
	echo "MASTERCARD=Liabilities:MasterCard" >> $CONFIG_FILE
	echo "CASH=Assets:Cash" >> $CONFIG_FILE
}

init_dataset() {
	if [[ -f $DB_DATAFILE ]]; then
		return
	fi

	touch $DB_DATAFILE
	echo -e "; Currenty used dataset by highled" >> $DB_DATAFILE
	echo ";" >> $DB_DATAFILE
	echo "; Simple opening balance entry" >> $DB_DATAFILE
	echo "; See more http://www.ledger-cli.org/3.0/doc/ledger3.html#Starting-up" >> $DB_DATAFILE
	echo >> $DB_DATAFILE
	echo -e "; 2015/06/21  Opening Balance" >> $DB_DATAFILE
	echo -e ";   Assets:Checking\t\t100 EUR" >> $DB_DATAFILE
	echo -e ";   Liabilities:Visa\t600 EUR" >> $DB_DATAFILE
	echo -e ";   Equity:Opening Balances" >> $DB_DATAFILE


	echo "Hey $USER! Your opening balance should be configred first."
	echo
	echo "If you have ledger file already, type:"
	echo "  cp <path-to-your-dataset> ./highled/current.ldg"
	echo
	echo "Create opening balance entry"
	echo "  (see more: http://www.ledger-cli.org/3.0/doc/ledger3.html#Starting-up)"
	echo
	echo "Edit dataset with nano or with your favourite editor:"
	echo "  nano .highled/current.ldg"
}

init_db() {
	if [[ ! -d $DB_DIR ]]; then
		mkdir $DB_DIR
	fi

	init_config
	init_dataset
}

flush_db() {
	if [[ -d $DB_DIR ]]; then
		rm -R $DB_DIR
	fi
}

rm_alias() {
	local key=`echo $1 | tr '[:lower:]' '[:upper:]'`
	sed -i '' -e /^$key=/d $CONFIG_FILE
}

get_alias() {
	if [ ! -r $CONFIG_FILE ]; then
		return 0
	fi

	local __resultvar=$2
	local key=`echo $1 | tr '[:lower:]' '[:upper:]'`
	local line=`grep -e "^$key=" $CONFIG_FILE | head -1`

	if [[ -z $line ]]; then
		return 0
	fi

	local val=${line##$key=}
	if [[ "$__resultvar" ]]; then
        eval $__resultvar="'$val'"
    else
        echo "$val"
    fi
}

set_alias() {
	local key=`echo $1 | tr '[:lower:]' '[:upper:]'`
	# local KEY=`echo $1 | awk '{ print toupper($0) }'`
	local value=$2

	if [ ! -f $CONFIG_FILE ]; then
		init_config
	fi

	if [ ! -w $CONFIG_FILE ]; then
		echo "Configuration file is not writable"
		exit 1
	fi

	rm_default $KEY
	echo "$KEY=$VALUE" >> $CONFIG_FILE
}

pay() {
	# Usage:   ./highled pay <amount> for <expense> with <what> [<date>] [-d <description>]
	# Example: ./highled pay 10 for Lunch with Visa

	local usage="Usage: ./highled pay <amount> for <expense> with <what> [<date>] [-d <description>]"
	local amount_with_currency=$1
	local amount=${amount_with_currency//[^0-9.,]/}
	local currency=${amount_with_currency//[0-9.,]/}
	
	if [[ -z $amount ]]; then
		echo "Specify payment amount."
		echo $usage
		exit 1
	fi	

	if [[ -z $currency ]]; then
		get_alias "DEFAULT_CURRENCY" currency
	fi

	local pay_for
	local pay_with
	local when=`date "+%Y/%m/%d"`
	local description

	local processed="0"

	shift
	while [[ $# -gt 0 ]]; do
		local key=$1

		case $key in
			"for")
				processed=$[$processed+1]
				pay_for=$2
				shift
				;;

			"with")
				processed=$[$processed+1]
				pay_with=$2
				shift
				;;

			-d|--description)
				description=$2
				shift
				;;

			"yesterday"|"Yesterday")
				when=`date -v-1d "+%Y/%m/%d"`
				;;

			*)
				if [[ $key =~ ^[0-9]+(\/[0-9]+)+$ ]]; then
					when=$key
				else
					echo "$0 - illegal date: $key"
					echo "Use form YYYY/MM/DD or \"yesterday\" instead"
					exit 1
				fi
				;;				
		esac
		shift
	done

	if [[ $processed -lt "2" ]]; then
		echo "Payment amount, expense name and payment method are required."
		echo $usage
		exit 1
	fi

	get_alias $amount resolved_amount
	get_alias $pay_for resolved_pay_for
	get_alias $pay_with resolved_pay_with
	get_alias $description resolved_description

	amount=${resolved_amount:=$amount}
	pay_for=${resolved_pay_for:=$pay_for}
	pay_with=${resolved_pay_with:=$pay_with}
	description=${resolved_description:=$description}

	if [[ -z $description ]]; then
		description="$pay_for purchase with ${pay_with##*:}"
	fi

	echo -e "$when  $description"
	echo -e "  Expenses:$pay_for\t$amount $currency" 
	echo -e "  $pay_with"

	echo >> $DB_DATAFILE
	echo -e "$when  $description" >> $DB_DATAFILE
	echo -e "  Expenses:$pay_for\t$amount $currency" >> $DB_DATAFILE
	echo -e "  $pay_with" >> $DB_DATAFILE
}

show_last() {
	if [[ $PLATFORM == "darwin" ]]; then
		tail -r $DB_DATAFILE | grep -E '^[0-9]+\/[0-9]+' -m 1 -B 20 | tail -r
	elif [[ $PLATFORM == "linux" ]]; then
		tac $DB_DATAFILE | grep -E '^[0-9]+\/[0-9]+' -m 1 -B 20 | tac
	else
		echo "Your platform is not supported yet."
		exit 1
	fi
}

undo_last() {
	local lines
	if [[ $PLATFORM == "darwin" ]]; then
		lines=`tail -r $DB_DATAFILE | grep -E '^[0-9]+\/[0-9]+' -m 1 -B 20 | tail -r | wc -l`
	elif [[ $PLATFORM == "linux" ]]; then
		lines=`cat $DB_DATAFILE | grep -E '^[0-9]+\/[0-9]+' -m 1 -B 20 | cat | wc -l`
	else
		echo "Your platform is not supported yet."
		exit 1
	fi
	local i="0"
	while [ $i -lt $lines ]; do
		sed -i '' -e '$ d' $DB_DATAFILE
		i=$[$i+1]
	done
}

# Main
case $1 in
	"init")
		init_db
		;;

	"flush")
		flush_db
		;;

	"pay")
		init_db
		shift
		pay "$@"
		;;

	"last")
		init_db
		shift
		show_last
		;;

	"undo")
		init_db
		shift
		undo_last
		;;

	"set-alias")
		init_db
		shift
		set_alias "$@"
		;;

	"rm-alias")
		init_db
		shift
		rm_alias "$@"
		;;

	"show-alias")
		init_db
		if [[ -z $2 ]]; then
			cat $CONFIG_FILE | less
		else
			get_alias $2
		fi
		;;

	"exec")
		init_db
		shift
		ledger -f $DB_DATAFILE "$@"
		;;

	"print")
		echo -e "Dataset:\t$DB_DATAFILE"
		echo -e "Configuration:\t$CONFIG_FILE"
		;;

	*)
		print_usage
		exit
esac

}
